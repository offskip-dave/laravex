defmodule Laravex.Queue.Worker do
  @moduledoc "Queue: sync, database, and deferred drivers with ShouldQueue support."
  use GenServer

  @deferred_table :laravex_deferred_jobs

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(s) do
    ensure_deferred()
    {:ok, s}
  end

  @supported_connections ~w(sync database deferred redis)

  def push(job_mod, args \\ [], opts \\ []) when is_atom(job_mod) do
    connection =
      to_string(
        Keyword.get(opts, :connection) ||
          Laravex.Config.Repository.get("queue.default", "database")
      )

    ensure_connection!(connection)

    should_queue? =
      cond do
        Keyword.has_key?(opts, :sync) -> not Keyword.get(opts, :sync)
        function_exported?(job_mod, :should_queue?, 0) -> job_mod.should_queue?()
        true -> true
      end

    opts = Keyword.put(opts, :should_queue?, should_queue?)
    Laravex.Queue.Resolver.module(connection).push(job_mod, args, opts)
  end

  @doc false
  def push_sync(job_mod, args, opts) do
    try do
      result = dispatch_sync(job_mod, args)
      record_batch(opts, :ok)
      result
    rescue
      e ->
        record_batch(opts, :failed)
        reraise e, __STACKTRACE__
    end
  end

  defp record_batch(opts, status) do
    case Keyword.get(opts, :batch_id) do
      id when is_binary(id) and id != "" -> Laravex.Bus.record_job_finished(id, status, nil)
      _ -> :ok
    end
  end

  defp ensure_connection!(connection) do
    unless connection in @supported_connections do
      raise ArgumentError,
            "Queue connection #{inspect(connection)} is unsupported. " <>
              "Supported connections: #{Enum.join(@supported_connections, ", ")} " <>
              "(set QUEUE_CONNECTION=sync|database|deferred|redis)."
    end

    :ok
  end

  def dispatch_sync(job_mod, args \\ []) do
    case run_job(job_mod, List.wrap(args)) do
      {:skipped, _} -> :ok
      :ok -> :ok
      other -> other
    end
  end

  def work(opts \\ []) do
    once = Keyword.get(opts, :once, false)
    drain_deferred()
    do_work(once)
  end

  def push_database(job_mod, args, opts) do
    payload =
      %{
        "job" => Atom.to_string(job_mod),
        "args" => encode_args(args),
        "tries" => Keyword.get(opts, :tries, 1),
        "backoff" => Keyword.get(opts, :backoff, 0)
      }
      |> maybe_put_batch(opts)
      |> Laravex.Support.JSON.encode!()

    now = System.system_time(:second)
    delay = Keyword.get(opts, :delay, 0)
    queue = Keyword.get(opts, :queue, "default")

    Laravex.Database.Connection.execute(
      "INSERT INTO jobs (queue, payload, attempts, reserved_at, available_at, created_at) VALUES (?, ?, 0, NULL, ?, ?)",
      [queue, payload, now + delay, now]
    )

    :ok
  end

  defp maybe_put_batch(payload, opts) do
    case Keyword.get(opts, :batch_id) do
      id when is_binary(id) and id != "" -> Map.put(payload, "batch_id", id)
      _ -> payload
    end
  end

  def push_deferred(job_mod, args, opts) do
    ensure_deferred()
    delay = Keyword.get(opts, :delay, 0)
    available = System.system_time(:second) + delay

    :ets.insert(@deferred_table, {
      System.unique_integer([:positive]),
      %{job: job_mod, args: List.wrap(args), available_at: available}
    })

    :ok
  end

  defp drain_deferred do
    ensure_deferred()
    now = System.system_time(:second)

    @deferred_table
    |> :ets.tab2list()
    |> Enum.each(fn
      {id, %{job: mod, args: args, available_at: at}} when at <= now ->
        :ets.delete(@deferred_table, id)

        try do
          run_job(mod, args)
        rescue
          e -> Laravex.Log.Logger.error("Deferred job failed: #{Exception.message(e)}")
        end

      _ ->
        :ok
    end)
  end

  defp ensure_deferred do
    if :ets.whereis(@deferred_table) == :undefined do
      try do
        _ = :ets.new(@deferred_table, [:named_table, :public, :set])
        :ok
      rescue
        ArgumentError -> :ok
      end
    else
      :ok
    end
  end

  defp do_work(once) do
    now = System.system_time(:second)

    jobs =
      Laravex.Database.Connection.query(
        "SELECT * FROM jobs WHERE available_at <= ? AND reserved_at IS NULL ORDER BY id ASC LIMIT 1",
        [now]
      )

    case jobs do
      [job | _] ->
        process(job)
        unless once, do: do_work(false)
        :ok

      [] ->
        if once, do: :ok, else: (Process.sleep(1000); do_work(false))
    end
  rescue
    _ -> if once, do: :ok, else: (Process.sleep(1000); do_work(false))
  end

  defp process(%{"id" => id, "payload" => payload} = job) do
    Laravex.Database.Connection.execute(
      "UPDATE jobs SET reserved_at = ?, attempts = attempts + 1 WHERE id = ?",
      [System.system_time(:second), id]
    )

    attempts =
      case Map.get(job, "attempts") do
        n when is_integer(n) -> n + 1
        n when is_binary(n) -> String.to_integer(n) + 1
        _ -> 1
      end

    data =
      case Laravex.Support.JSON.decode(payload) do
        {:ok, decoded} -> decoded
        _ -> %{}
      end

    try do
      job_mod = resolve_job_module(data["job"])
      args = decode_args(data["args"] || [])

      case run_job(job_mod, args) do
        {:skipped, :duplicate} ->
          Laravex.Database.Connection.execute("UPDATE jobs SET reserved_at = NULL WHERE id = ?", [id])

        {:skipped, :retry_until} ->
          Laravex.Database.Connection.execute("DELETE FROM jobs WHERE id = ?", [id])
          Laravex.Bus.record_job_finished(data["batch_id"], :failed, id)

        {:error, :timeout} = err ->
          Laravex.Observability.record_job(job_mod, err)
          fail(job, data, attempts, RuntimeError.exception("Job exceeded soft timeout"))

        result ->
          Laravex.Observability.record_job(job_mod, result)
          Laravex.Database.Connection.execute("DELETE FROM jobs WHERE id = ?", [id])
          Laravex.Bus.record_job_finished(data["batch_id"], :ok, id)
          result
      end
    rescue
      e ->
        Laravex.Observability.record_job(Map.get(data, "job"), {:error, Exception.message(e)})
        fail(job, data, attempts, e)
    end
  end

  defp resolve_job_module(name) when is_binary(name) do
    mod = String.to_atom(name)

    case Code.ensure_loaded(mod) do
      {:module, ^mod} ->
        mod

      {:error, reason} ->
        raise "Job module #{name} could not be loaded: #{inspect(reason)}"
    end
  end

  defp fail(%{"id" => id, "payload" => payload, "queue" => queue}, data, attempts, error) do
    max_tries = parse_int(Map.get(data, "tries"), 1)
    backoff = parse_int(Map.get(data, "backoff"), 0)

    if attempts < max_tries do
      available_at = System.system_time(:second) + max(backoff, 0)

      Laravex.Database.Connection.execute(
        "UPDATE jobs SET reserved_at = NULL, available_at = ? WHERE id = ?",
        [available_at, id]
      )
    else
      Laravex.Database.Connection.execute("DELETE FROM jobs WHERE id = ?", [id])

      if Laravex.Database.Schema.has_table?("failed_jobs") do
        Laravex.Database.Connection.execute(
          "INSERT INTO failed_jobs (uuid, connection, queue, payload, exception, failed_at) VALUES (?, ?, ?, ?, ?, ?)",
          [
            Laravex.Support.Helpers.str_random(16),
            "database",
            queue,
            payload,
            Exception.message(error),
            DateTime.utc_now() |> DateTime.to_iso8601()
          ]
        )
      end

      Laravex.Bus.record_job_finished(Map.get(data, "batch_id"), :failed, id)
    end
  end

  defp parse_int(n, _default) when is_integer(n), do: n

  defp parse_int(n, default) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      :error -> default
    end
  end

  defp parse_int(_, default), do: default

  @doc false
  def encode_args(args) when is_list(args), do: Enum.map(args, &encode_arg/1)
  def encode_args(args), do: [encode_arg(args)]

  defp encode_arg(arg)
       when is_binary(arg) or is_number(arg) or is_boolean(arg) or is_nil(arg) do
    arg
  end

  defp encode_arg(arg) when is_atom(arg), do: Atom.to_string(arg)

  defp encode_arg(arg) do
    %{"__bin__" => Base.encode64(:erlang.term_to_binary(arg))}
  end

  defp decode_args(args) when is_list(args), do: Enum.map(args, &decode_arg/1)
  defp decode_args(args), do: [decode_arg(args)]

  defp decode_arg(%{"__bin__" => bin}) when is_binary(bin) do
    :erlang.binary_to_term(Base.decode64!(bin))
  end

  defp decode_arg(arg), do: arg

  def failed_jobs do
    if Laravex.Database.Schema.has_table?("failed_jobs") do
      Laravex.Database.Connection.query(
        "SELECT id, uuid, connection, queue, payload, exception, failed_at FROM failed_jobs ORDER BY id DESC"
      )
    else
      []
    end
  rescue
    _ -> []
  end

  def retry_failed(id_or_uuid) do
    row = find_failed(id_or_uuid)

    if is_nil(row) do
      {:error, :not_found}
    else
      case Laravex.Support.JSON.decode(row["payload"] || "") do
        {:ok, %{"job" => job, "args" => args}} ->
          job_mod = resolve_job_module(job)
          push(job_mod, args || [], [])
          forget_failed(row["uuid"] || row["id"])
          {:ok, row}

        _ ->
          {:error, :bad_payload}
      end
    end
  end

  def forget_failed(id_or_uuid) do
    row = find_failed(id_or_uuid)

    if row && Laravex.Database.Schema.has_table?("failed_jobs") do
      Laravex.Database.Connection.execute("DELETE FROM failed_jobs WHERE id = ? OR uuid = ?", [
        row["id"],
        row["uuid"]
      ])

      :ok
    else
      :error
    end
  rescue
    _ -> :error
  end

  def flush_failed do
    if Laravex.Database.Schema.has_table?("failed_jobs") do
      Laravex.Database.Connection.execute("DELETE FROM failed_jobs")
    end

    :ok
  rescue
    _ -> :ok
  end

  defp run_job(job_mod, args) when is_atom(job_mod) do
    if past_retry_until?(job_mod) do
      {:skipped, :retry_until}
    else
      started_at = System.monotonic_time(:millisecond)

      run =
        if unique_job?(job_mod) do
          lock = unique_lock(job_mod, args)

          if Laravex.Cache.Manager.get_lock(lock) do
            try do
              execute_handle(job_mod, args, started_at)
            after
              Laravex.Cache.Manager.release(lock)
            end
          else
            {:skipped, :duplicate}
          end
        else
          execute_handle(job_mod, args, started_at)
        end

      run
    end
  end

  defp execute_handle(job_mod, args, started_at) do
    result = job_mod.handle(List.wrap(args))

    case soft_timeout?(job_mod, started_at) do
      true ->
        Laravex.Log.Logger.warning("Job #{inspect(job_mod)} exceeded soft timeout/0 limit")
        {:error, :timeout}

      false ->
        result
    end
  end

  defp unique_job?(mod) do
    function_exported?(mod, :unique_id, 1) or function_exported?(mod, :unique_for, 0)
  end

  defp unique_lock(job_mod, args) do
    id =
      if function_exported?(job_mod, :unique_id, 1) do
        to_string(job_mod.unique_id(List.wrap(args)))
      else
        inspect(args)
      end

    seconds =
      if function_exported?(job_mod, :unique_for, 0) do
        job_mod.unique_for()
      else
        3600
      end

    Laravex.Cache.Manager.lock("laravex:unique_job:#{job_mod}:#{id}", seconds)
  end

  defp past_retry_until?(job_mod) do
    if function_exported?(job_mod, :retry_until, 0) do
      deadline = job_mod.retry_until()
      now = System.system_time(:second)
      deadline_ts = coerce_unix(deadline)
      is_integer(deadline_ts) and now > deadline_ts
    else
      false
    end
  end

  defp soft_timeout?(job_mod, started_at_ms) do
    if function_exported?(job_mod, :timeout, 0) do
      limit_sec = job_mod.timeout()
      elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms
      is_integer(limit_sec) and limit_sec > 0 and elapsed_ms > limit_sec * 1000
    else
      false
    end
  end

  defp coerce_unix(%DateTime{} = dt), do: DateTime.to_unix(dt)
  defp coerce_unix(%NaiveDateTime{} = ndt), do: NaiveDateTime.diff(ndt, ~N[1970-01-01 00:00:00], :second)

  defp coerce_unix(n) when is_integer(n), do: n

  defp coerce_unix(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> DateTime.to_unix(dt)
      _ -> nil
    end
  end

  defp coerce_unix(_), do: nil

  defp find_failed(id_or_uuid) do
    id = to_string(id_or_uuid)

    if Laravex.Database.Schema.has_table?("failed_jobs") do
      case Laravex.Database.Connection.query(
             "SELECT * FROM failed_jobs WHERE uuid = ? OR CAST(id AS TEXT) = ? LIMIT 1",
             [id, id]
           ) do
        [row | _] -> row
        _ -> nil
      end
    else
      nil
    end
  rescue
    _ -> nil
  end
end

defmodule Laravex.Queue.Job do
  @moduledoc "Base job behaviour with ShouldQueue-style opts."
  @callback handle(args :: list()) :: any()

  defmacro __using__(opts \\ []) do
    queue? = Keyword.get(opts, :queue, true)

    quote do
      @behaviour Laravex.Queue.Job

      def should_queue?, do: unquote(queue?)

      def dispatch(args \\ [], opts \\ []) do
        Laravex.Queue.Worker.push(__MODULE__, List.wrap(args), opts)
      end

      def dispatch_sync(args \\ []) do
        Laravex.Queue.Worker.dispatch_sync(__MODULE__, List.wrap(args))
      end

      defoverridable should_queue?: 0
    end
  end
end
