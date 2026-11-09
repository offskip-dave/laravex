defmodule Laravex.Database.Connection do
  @moduledoc """
  Database facade — multi-connection aware.

  Default connection comes from `database.default`. Switch per-process with
  `using_connection/2` or set a query/model connection.
  """

  @conn_key :laravex_db_connection

  def current_name do
    Process.get(@conn_key) ||
      to_string(Laravex.Config.Repository.get("database.default", "sqlite"))
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
    adapter().execute(sql, bindings)
  end

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

  def transaction(fun) when is_function(fun, 0) do
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
  end
end
