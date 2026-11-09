defmodule Laravex.Database.Adapters.Native.Mysql do
  @moduledoc "MySQL/MariaDB via MyXQL (`client: \"native\"`)."
  @behaviour Laravex.Database.Adapter

  @impl true
  def path do
    c = Laravex.Database.Connection.config()
    "#{Map.get(c, "host", "127.0.0.1")}:#{Map.get(c, "port", "3306")}/#{Map.get(c, "database", "laravex")}"
  end

  @impl true
  def ensure_database! do
    Laravex.Database.Pool.ensure_started!(Laravex.Database.Connection.current_name())
    path()
  end

  @impl true
  def query(sql, bindings \\ []) do
    ensure_database!()
    name = Laravex.Database.Connection.current_name()

    Laravex.Database.Pool.checkout(name, fn pid ->
      case MyXQL.query(pid, sql, List.wrap(bindings)) do
        {:ok, %{rows: rows, columns: columns}} when is_list(rows) ->
          cols = Enum.map(columns, &to_string/1)
          Enum.map(rows, fn row -> cols |> Enum.zip(List.wrap(row)) |> Map.new() end)

        {:ok, _} ->
          []

        {:error, err} ->
          raise "MySQL native error: #{Exception.message(err)}"
      end
    end)
  end

  @impl true
  def execute(sql, bindings \\ []) do
    _ = query(sql, bindings)
    :ok
  end
end
