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

  def push(job_mod, args \\ [], opts \\ []) when is_atom(job_mod) do
    connection =
      Keyword.get(opts, :connection) ||
        Laravex.Config.Repository.get("queue.default", "database")

    should_queue? =
      cond do
        Keyword.has_key?(opts, :sync) -> not Keyword.get(opts, :sync)
        function_exported?(job_mod, :should_queue?, 0) -> job_mod.should_queue?()
        true -> true
      end

    cond do
      connection == "sync" or not should_queue? ->
        dispatch_sync(job_mod, args)

      connection == "deferred" ->
        push_deferred(job_mod, args, opts)

      true ->
        push_database(job_mod, args, opts)
    end
  end

  def dispatch_sync(job_mod, args \\ []) do
    job_mod.handle(List.wrap(args))
    :ok
  end

  def work(opts \\ []) do
    once = Keyword.get(opts, :once, false)
    drain_deferred()
    do_work(once)
  end

  defp push_database(job_mod, args, opts) do
    payload =
      Laravex.Support.JSON.encode!(%{
        "job" => Atom.to_string(job_mod),
        "args" => encode_args(args),
        "tries" => Keyword.get(opts, :tries, 1)
      })

    now = System.system_time(:second)
    delay = Keyword.get(opts, :delay, 0)
    queue = Keyword.get(opts, :queue, "default")

    Laravex.Database.Connection.execute(
      "INSERT INTO jobs (queue, payload, attempts, reserved_at, available_at, created_at) VALUES (?, ?, 0, NULL, ?, ?)",
      [queue, payload, now + delay, now]
    )

    :ok
  end

  defp push_deferred(job_mod, args, opts) do
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
          mod.handle(args)
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
        :ets.new(@deferred_table, [:named_table, :public, :set])
      rescue
        ArgumentError -> :ok
      end
    end

    :ok
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

    data =
      case Laravex.Support.JSON.decode(payload) do
        {:ok, decoded} -> decoded
        _ -> %{}
      end

    try do
      job_mod = resolve_job_module(data["job"])
      args = data["args"] || []
      result = job_mod.handle(args)
      Laravex.Observability.record_job(job_mod, result)
      Laravex.Database.Connection.execute("DELETE FROM jobs WHERE id = ?", [id])
    rescue
      e ->
        Laravex.Observability.record_job(Map.get(data, "job"), {:error, Exception.message(e)})
        fail(job, e)
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

  defp fail(%{"id" => id, "payload" => payload, "queue" => queue}, error) do
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
  end

  defp encode_args(args) when is_list(args), do: Enum.map(args, &to_string/1)
  defp encode_args(args), do: [to_string(args)]
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
