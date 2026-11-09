defmodule Laravex.Database.Adapters.Native.Sqlite do
  @moduledoc "SQLite via Exqlite + DBConnection pool (`client: \"native\"`)."
  @behaviour Laravex.Database.Adapter

  @impl true
  def path do
    cfg = Laravex.Database.Connection.config()
    Map.get(cfg, "database") || Path.join(File.cwd!(), "database/database.sqlite")
  end

  @impl true
  def ensure_database! do
    p = path()
    File.mkdir_p!(Path.dirname(p))
    unless File.exists?(p), do: File.write!(p, "")
    _ = Laravex.Database.Pool.ensure_started!(Laravex.Database.Connection.current_name())
    p
  end

  @impl true
  def query(sql, bindings \\ []) do
    ensure_database!()
    name = Laravex.Database.Connection.current_name()
    params = List.wrap(bindings)

    Laravex.Database.Pool.checkout(name, fn pid ->
      case Exqlite.query(pid, sql, params) do
        {:ok, %{rows: rows, columns: columns}} ->
          cols = Enum.map(columns || [], &to_string/1)

          Enum.map(rows || [], fn row ->
            cols |> Enum.zip(List.wrap(row)) |> Map.new()
          end)

        {:error, err} ->
          raise "SQLite native error: #{inspect(err)}"
      end
    end)
  end

  @impl true
  def execute(sql, bindings \\ []) do
    _ = query(sql, bindings)
    :ok
  end
end
