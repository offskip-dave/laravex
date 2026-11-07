defmodule Laravex.Database.Adapters.Sqlite do
  @moduledoc "SQLite via the `sqlite3` CLI (no Hex deps)."
  @behaviour Laravex.Database.Adapter

  @impl true
  def path do
    configured = Laravex.Config.Repository.get("database.connections.sqlite.database")

    if is_binary(configured) and configured != "" do
      configured
    else
      Path.join(Laravex.Foundation.Application.base_path(), "database/database.sqlite")
    end
  end

  @impl true
  def ensure_database! do
    p = path()
    File.mkdir_p!(Path.dirname(p))
    unless File.exists?(p), do: File.write!(p, "")
    p
  end

  @impl true
  def query(sql, bindings \\ []) do
    sql = Laravex.Database.SqlBind.bind(sql, bindings)
    db = ensure_database!()
    {output, status} = System.cmd("sqlite3", ["-json", db, sql], stderr_to_stdout: true)

    if status != 0 do
      raise "SQLite error: #{output}"
    end

    output = String.trim(output)
    if output == "", do: [], else: elem(Laravex.Support.JSON.decode_array(output), 1)
  end

  @impl true
  def execute(sql, bindings \\ []) do
    sql = Laravex.Database.SqlBind.bind(sql, bindings)
    db = ensure_database!()
    {output, status} = System.cmd("sqlite3", [db, sql], stderr_to_stdout: true)
    if status != 0, do: raise("SQLite error: #{output}")
    :ok
  end

end
