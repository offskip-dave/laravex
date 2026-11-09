defmodule Laravex.Database.Adapters.Native.Postgres do
  @moduledoc "PostgreSQL via Postgrex (`client: \"native\"`)."
  @behaviour Laravex.Database.Adapter

  @impl true
  def path do
    c = Laravex.Database.Connection.config()
    "#{Map.get(c, "host", "127.0.0.1")}:#{Map.get(c, "port", "5432")}/#{Map.get(c, "database", "laravex")}"
  end

  @impl true
  def ensure_database! do
    name = Laravex.Database.Connection.current_name()
    Laravex.Database.Pool.ensure_started!(name)
    path()
  end

  @impl true
  def query(sql, bindings \\ []) do
    ensure_database!()
    name = Laravex.Database.Connection.current_name()
    {sql, params} = rewrite_placeholders(sql, List.wrap(bindings))

    Laravex.Database.Pool.checkout(name, fn pid ->
      case Postgrex.query(pid, sql, params) do
        {:ok, %{rows: rows, columns: columns}} ->
          cols = Enum.map(columns, &to_string/1)

          Enum.map(rows, fn row ->
            cols |> Enum.zip(row) |> Map.new()
          end)

        {:error, err} ->
          raise "PostgreSQL native error: #{Exception.message(err)}"
      end
    end)
  end

  @impl true
  def execute(sql, bindings \\ []) do
    _ = query(sql, bindings)
    :ok
  end

  # Convert `?` placeholders to `$1..$n` for Postgrex.
  defp rewrite_placeholders(sql, bindings) do
    {sql, _} =
      Enum.reduce(1..max(length(bindings), 1), {sql, 1}, fn _, {acc, n} ->
        if String.contains?(acc, "?") do
          {String.replace(acc, "?", "$#{n}", global: false), n + 1}
        else
          {acc, n}
        end
      end)

    if bindings == [] and not String.contains?(sql, "$"), do: {sql, []}, else: {sql, bindings}
  end
end
