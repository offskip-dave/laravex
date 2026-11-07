defmodule Laravex.Database.Connection do
  @moduledoc """
  Database facade — delegates to the connection adapter from `database.default`.
  """

  def adapter, do: Laravex.Database.Resolver.current()

  def adapter_name do
    to_string(Laravex.Config.Repository.get("database.default", "sqlite"))
  end

  def random_order_fragment do
    case adapter_name() do
      name when name in ["mysql", "mariadb"] -> "RAND()"
      _ -> "RANDOM()"
    end
  end

  def path, do: adapter().path()
  def ensure_database!, do: adapter().ensure_database!()
  def query(sql, bindings \\ []), do: adapter().query(sql, bindings)
  def execute(sql, bindings \\ []), do: adapter().execute(sql, bindings)

  def last_insert_id do
    case adapter_name() do
      "mysql" ->
        case query("SELECT LAST_INSERT_ID() AS id") do
          [%{"id" => id}] -> id
          _ -> nil
        end

      "mariadb" ->
        case query("SELECT LAST_INSERT_ID() AS id") do
          [%{"id" => id}] -> id
          _ -> nil
        end

      name when name in ["pgsql", "postgres"] ->
        case query("SELECT lastval() AS id") do
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
