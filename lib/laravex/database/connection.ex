defmodule Laravex.Database.Connection do
  @moduledoc """
  SQLite connection via the `sqlite3` CLI (no Hex deps).
  """

  def path do
    configured = Laravex.Config.Repository.get("database.connections.sqlite.database")

    if is_binary(configured) and configured != "" do
      configured
    else
      Path.join(Laravex.Foundation.Application.base_path(), "database/database.sqlite")
    end
  end

  def ensure_database! do
    p = path()
    File.mkdir_p!(Path.dirname(p))
    unless File.exists?(p), do: File.write!(p, "")
    p
  end

  def query(sql, bindings \\ []) do
    sql = bind(sql, bindings)
    db = ensure_database!()
    {output, status} = System.cmd("sqlite3", ["-json", db, sql], stderr_to_stdout: true)

    if status != 0 do
      raise "SQLite error: #{output}"
    end

    output = String.trim(output)
    if output == "", do: [], else: elem(Laravex.Support.JSON.decode_array(output), 1)
  end

  def execute(sql, bindings \\ []) do
    sql = bind(sql, bindings)
    db = ensure_database!()
    {output, status} = System.cmd("sqlite3", [db, sql], stderr_to_stdout: true)
    if status != 0, do: raise("SQLite error: #{output}")
    :ok
  end

  def last_insert_id do
    case query("SELECT last_insert_rowid() AS id") do
      [%{"id" => id}] -> id
      _ -> nil
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

  defp bind(sql, bindings) do
    Enum.reduce(bindings, sql, fn val, acc ->
      String.replace(acc, "?", quote_val(val), global: false)
    end)
  end

  defp quote_val(nil), do: "NULL"
  defp quote_val(true), do: "1"
  defp quote_val(false), do: "0"
  defp quote_val(%DateTime{} = v), do: quote_val(DateTime.to_iso8601(v))
  defp quote_val(v) when is_integer(v) or is_float(v), do: to_string(v)

  defp quote_val(v) do
    "'" <> String.replace(to_string(v), "'", "''") <> "'"
  end
end
