defmodule Laravex.Database.Connection do
  @moduledoc """
  Database facade — multi-connection aware.

  Default connection comes from `database.default`. Switch per-process with
  `using_connection/2` or set a query/model connection.
  """

  @conn_key :laravex_db_connection
  @modified_key :laravex_db_records_modified

  def current_name do
    Process.get(@conn_key) ||
      to_string(Laravex.Config.Repository.get("database.default", "sqlite"))
  end

  @doc "Mark that writes occurred (Laravel sticky read/write)."
  def records_have_been_modified(flag \\ true) do
    Process.put(@modified_key, flag == true)
    :ok
  end

  def has_modified_records?, do: Process.get(@modified_key, false) == true

  def forget_record_modification_state do
    Process.delete(@modified_key)
    :ok
  end

  @doc """
  Run `fun` without changing sticky modification state (Laravel `withoutAffectingStickiness`).
  """
  def without_affecting_stickiness(fun) when is_function(fun, 0) do
    prev = Process.get(@modified_key)

    try do
      fun.()
    after
      if is_nil(prev) do
        Process.delete(@modified_key)
      else
        Process.put(@modified_key, prev)
      end
    end
  end

  def without_affecting_stickiness(fun) when is_function(fun, 1) do
    without_affecting_stickiness(fn -> fun.(__MODULE__) end)
  end

  def config(name \\ nil) do
    name = Laravex.Database.Resolver.normalize_name(name || current_name())

    Laravex.Config.Repository.get("database.connections.#{name}") ||
      Laravex.Config.Repository.get("database.connections.sqlite") ||
      %{}
  end

  @doc "Run `fun` with `name` as the process-local default connection."
  def using_connection(name, fun) when is_function(fun, 0) do
    prev = Process.get(@conn_key)
    Process.put(@conn_key, Laravex.Database.Resolver.normalize_name(name))

    try do
      fun.()
    after
      if prev do
        Process.put(@conn_key, prev)
      else
        Process.delete(@conn_key)
      end
    end
  end

  def connection(name), do: using_connection(name, fn -> current_name() end)

  def adapter(name \\ nil), do: Laravex.Database.Resolver.module(name)

  def adapter_name(name \\ nil),
    do: Laravex.Database.Resolver.normalize_name(name || current_name())

  def random_order_fragment do
    case adapter_name() do
      name when name in ["mysql", "mariadb"] -> "RAND()"
      "sqlsrv" -> "NEWID()"
      _ -> "RANDOM()"
    end
  end

  def path(name \\ nil), do: adapter(name).path()
  def ensure_database!(name \\ nil), do: adapter(name).ensure_database!()

  def query(sql, bindings \\ []) do
    adapter().query(sql, bindings)
  end

  def execute(sql, bindings \\ []) do
    result = adapter().execute(sql, bindings)
    maybe_mark_write(sql)
    result
  end

  defp maybe_mark_write(sql) when is_binary(sql) do
    trimmed = sql |> String.trim_leading() |> String.upcase()

    if String.starts_with?(trimmed, ["INSERT", "UPDATE", "DELETE", "REPLACE", "TRUNCATE"]) do
      records_have_been_modified(true)
    end
  end

  defp maybe_mark_write(_), do: :ok

  def last_insert_id do
    case adapter_name() do
      name when name in ["mysql", "mariadb"] ->
        case query("SELECT LAST_INSERT_ID() AS id") do
          [%{"id" => id}] -> id
          _ -> nil
        end

      name when name in ["pgsql", "postgres"] ->
        case query("SELECT lastval() AS id") do
          [%{"id" => id}] -> id
          _ -> nil
        end

      "sqlsrv" ->
        case query("SELECT SCOPE_IDENTITY() AS id") do
          [%{"id" => id}] -> id
          _ -> nil
        end

      _ ->
        case query("SELECT last_insert_rowid() AS id") do
          [%{"id" => id}] -> id
          _ -> nil
        end
    end
  end

  @longer_key :laravex_transaction_longer_than
  @tx_level_key :laravex_transaction_level
  @tx_started_key :laravex_transaction_started_at

  @doc """
  Register a callback when a transaction runs longer than `threshold` milliseconds
  (Laravel `Connection::whenTransactionRunsLongerThan`).

  Handler receives `(connection_mod, event, duration_ms)` where event is
  `:committed` or `:rolled_back`.
  """
  def when_transaction_runs_longer_than(threshold, handler)
      when is_number(threshold) and is_function(handler, 3) do
    hooks = Process.get(@longer_key, [])
    Process.put(@longer_key, hooks ++ [{threshold * 1.0, handler}])
    :ok
  end

  def transaction(fun) when is_function(fun, 0) do
    level = Process.get(@tx_level_key, 0)
    Process.put(@tx_level_key, level + 1)

    if level == 0 do
      Process.put(@tx_started_key, System.monotonic_time(:millisecond))
    end

    try do
      result =
        if Laravex.Database.Resolver.native?(current_name()) do
          Laravex.Database.Pool.transaction(current_name(), fun)
        else
          execute("BEGIN")

          try do
            result = fun.()
            execute("COMMIT")
            {:ok, result}
          rescue
            e ->
              _ = execute("ROLLBACK")
              reraise e, __STACKTRACE__
          end
        end

      notify_transaction_duration(:committed)
      result
    rescue
      e ->
        notify_transaction_duration(:rolled_back)
        reraise e, __STACKTRACE__
    after
      Process.put(@tx_level_key, level)

      if level == 0 do
        Process.delete(@tx_started_key)
      end
    end
  end

  @doc false
  def notify_transaction_duration(event) do
    if Process.get(@tx_level_key, 0) == 1 do
      started = Process.get(@tx_started_key)

      if is_integer(started) do
        duration = System.monotonic_time(:millisecond) - started

        Enum.each(Process.get(@longer_key, []), fn {threshold, handler} ->
          if duration > threshold, do: handler.(__MODULE__, event, duration * 1.0)
        end)
      end
    end
  rescue
    _ -> :ok
  end
end
