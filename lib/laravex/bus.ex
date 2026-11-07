defmodule Laravex.Bus do
  @moduledoc """
  Job chain + batch helpers (Laravel Bus lite).

      Laravex.Bus.chain([{App.Jobs.A, [1]}, {App.Jobs.B, [1]}])

      batch = Laravex.Bus.batch([
        {App.Jobs.ImportRow, [1]},
        {App.Jobs.ImportRow, [2]}
      ], name: "Import")

      Laravex.Bus.then(batch, {App.Jobs.NotifyDone, :handle, [[]]})
  """

  defmodule Batch do
    defstruct [
      :id,
      :name,
      :total_jobs,
      :pending_jobs,
      :failed_jobs,
      :options,
      :created_at,
      :finished_at,
      :cancelled_at
    ]
  end

  def chain(jobs) when is_list(jobs) do
    Enum.each(jobs, fn
      {mod, args} when is_atom(mod) ->
        Laravex.Queue.Worker.dispatch_sync(mod, List.wrap(args))

      mod when is_atom(mod) ->
        Laravex.Queue.Worker.dispatch_sync(mod, [])

      other ->
        raise ArgumentError, "Bus.chain expects {JobMod, args} or JobMod, got: #{inspect(other)}"
    end)

    :ok
  end

  def dispatch(job_mod, args \\ [], opts \\ []) when is_atom(job_mod) do
    Laravex.Queue.Worker.push(job_mod, List.wrap(args), opts)
  end

  def dispatch_sync(job_mod, args \\ []) when is_atom(job_mod) do
    Laravex.Queue.Worker.dispatch_sync(job_mod, List.wrap(args))
  end

  @doc """
  Dispatch a batch of jobs tracked in `job_batches`.

  Options: `:name`, `:then` / `:catch` / `:finally` as `{mod, fun, args}` MFA,
  `:connection`, `:queue`, `:tries`, `:delay`.
  """
  def batch(jobs, opts \\ []) when is_list(jobs) do
    unless Laravex.Database.Schema.has_table?("job_batches") do
      raise "job_batches table is missing — run migrations first"
    end

    id = Laravex.Support.Str.uuid()
    name = Keyword.get(opts, :name, "") |> to_string()
    total = length(jobs)
    now = System.system_time(:second)

    options =
      %{
        "then" => encode_mfa(Keyword.get(opts, :then)),
        "catch" => encode_mfa(Keyword.get(opts, :catch)),
        "finally" => encode_mfa(Keyword.get(opts, :finally))
      }
      |> Laravex.Support.JSON.encode!()

    Laravex.Database.Connection.execute(
      """
      INSERT INTO job_batches
        (id, name, total_jobs, pending_jobs, failed_jobs, failed_job_ids, options, cancelled_at, created_at, finished_at)
      VALUES (?, ?, ?, ?, 0, ?, ?, NULL, ?, NULL)
      """,
      [id, name, total, total, "[]", options, now]
    )

    if total == 0 do
      Laravex.Database.Connection.execute(
        "UPDATE job_batches SET pending_jobs = 0, finished_at = ? WHERE id = ?",
        [now, id]
      )

      fire_callbacks(find_batch(id))
    else
      Enum.each(jobs, fn
        {mod, args} when is_atom(mod) ->
          Laravex.Queue.Worker.push(mod, List.wrap(args), batch_push_opts(opts, id))

        mod when is_atom(mod) ->
          Laravex.Queue.Worker.push(mod, [], batch_push_opts(opts, id))

        other ->
          raise ArgumentError, "Bus.batch expects {JobMod, args} or JobMod, got: #{inspect(other)}"
      end)
    end

    find_batch(id)
  end

  def then(%Batch{id: id}, mfa), do: store_callback(id, "then", mfa)
  def then(id, mfa) when is_binary(id), do: store_callback(id, "then", mfa)

  def catch_callback(%Batch{id: id}, mfa), do: store_callback(id, "catch", mfa)
  def catch_callback(id, mfa) when is_binary(id), do: store_callback(id, "catch", mfa)

  def finally(%Batch{id: id}, mfa), do: store_callback(id, "finally", mfa)
  def finally(id, mfa) when is_binary(id), do: store_callback(id, "finally", mfa)

  def find_batch(id) when is_binary(id) do
    case Laravex.Database.Connection.query("SELECT * FROM job_batches WHERE id = ? LIMIT 1", [id]) do
      [row | _] -> from_row(row)
      _ -> nil
    end
  end

  def record_job_finished(batch_id, status) when is_binary(batch_id) and status in [:ok, :failed] do
    batch = find_batch(batch_id)
    if is_nil(batch), do: :ok, else: do_record(batch, status)
  end

  def record_job_finished(_, _), do: :ok

  defp do_record(%Batch{} = batch, status) do
    pending = max(batch.pending_jobs - 1, 0)
    failed = if status == :failed, do: batch.failed_jobs + 1, else: batch.failed_jobs
    finished_at = if pending == 0, do: System.system_time(:second), else: batch.finished_at

    Laravex.Database.Connection.execute(
      "UPDATE job_batches SET pending_jobs = ?, failed_jobs = ?, finished_at = ? WHERE id = ?",
      [pending, failed, finished_at, batch.id]
    )

    if pending == 0 do
      fire_callbacks(find_batch(batch.id))
    end

    :ok
  end

  defp fire_callbacks(nil), do: :ok

  defp fire_callbacks(%Batch{} = batch) do
    opts = decode_options(batch.options)

    if batch.failed_jobs > 0 do
      invoke_mfa(opts["catch"], batch)
    else
      invoke_mfa(opts["then"], batch)
    end

    invoke_mfa(opts["finally"], batch)
    :ok
  end

  defp store_callback(id, key, mfa) do
    batch = find_batch(id)

    if batch do
      opts =
        batch.options
        |> decode_options()
        |> Map.put(key, encode_mfa(mfa))

      Laravex.Database.Connection.execute("UPDATE job_batches SET options = ? WHERE id = ?", [
        Laravex.Support.JSON.encode!(opts),
        id
      ])
    end

    find_batch(id)
  end

  defp batch_push_opts(opts, batch_id) do
    opts
    |> Keyword.take([:connection, :queue, :tries, :delay, :sync])
    |> Keyword.put(:batch_id, batch_id)
  end

  defp encode_mfa(nil), do: nil
  defp encode_mfa({mod, fun, args}) when is_atom(mod) and is_atom(fun) and is_list(args) do
    %{"mod" => Atom.to_string(mod), "fun" => Atom.to_string(fun), "args" => args}
  end

  defp encode_mfa(other) do
    raise ArgumentError, "Bus callback must be {mod, fun, args}, got: #{inspect(other)}"
  end

  defp invoke_mfa(nil, _batch), do: :ok

  defp invoke_mfa(%{"mod" => mod, "fun" => fun, "args" => args}, batch) do
    mod = String.to_atom(mod)
    fun = String.to_atom(fun)
    Code.ensure_loaded(mod)
    apply(mod, fun, [batch | List.wrap(args)])
  rescue
    e -> Laravex.Log.Logger.error("Bus batch callback failed: #{Exception.message(e)}")
  end

  defp invoke_mfa(_, _), do: :ok

  defp decode_options(nil), do: %{}
  defp decode_options(json) when is_binary(json) do
    case Laravex.Support.JSON.decode(json) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp decode_options(map) when is_map(map), do: map

  defp from_row(row) do
    %Batch{
      id: row["id"],
      name: row["name"],
      total_jobs: row["total_jobs"] || 0,
      pending_jobs: row["pending_jobs"] || 0,
      failed_jobs: row["failed_jobs"] || 0,
      options: row["options"],
      created_at: row["created_at"],
      finished_at: row["finished_at"],
      cancelled_at: row["cancelled_at"]
    }
  end
end
