defmodule Laravex.Database.Adapters.Native.SqlServer do
  @moduledoc "SQL Server via TDS (`client: \"native\"`)."
  @behaviour Laravex.Database.Adapter

  @impl true
  def path do
    c = Laravex.Database.Connection.config()
    "#{Map.get(c, "host", "localhost")}:#{Map.get(c, "port", "1433")}/#{Map.get(c, "database", "laravex")}"
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
    {sql, params} = rewrite_placeholders(sql, List.wrap(bindings))

    Laravex.Database.Pool.checkout(name, fn pid ->
      case Tds.query(pid, sql, params) do
        {:ok, %{rows: rows, columns: columns}} ->
          cols = Enum.map(columns, &to_string/1)
          Enum.map(rows, fn row -> cols |> Enum.zip(List.wrap(row)) |> Map.new() end)

        {:error, err} ->
          raise "SQL Server native error: #{Exception.message(err)}"
      end
    end)
  end

  @impl true
  def execute(sql, bindings \\ []) do
    _ = query(sql, bindings)
    :ok
  end

  defp rewrite_placeholders(sql, bindings) do
    {sql, _} =
      Enum.reduce(1..max(length(bindings), 1), {sql, 1}, fn _, {acc, n} ->
        if String.contains?(acc, "?") do
          {String.replace(acc, "?", "@p#{n}", global: false), n + 1}
        else
          {acc, n}
        end
      end)

    params =
      bindings
      |> Enum.with_index(1)
      |> Enum.map(fn {v, i} -> %Tds.Parameter{name: "@p#{i}", value: v} end)

    {sql, params}
  end
end
