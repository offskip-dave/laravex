defmodule Laravex.Database.Adapters.Postgres do
  @moduledoc "PostgreSQL via the `psql` CLI (no Hex deps)."
  @behaviour Laravex.Database.Adapter

  @impl true
  def path do
    c = cfg()
    host = Map.get(c, "host", "127.0.0.1")
    port = Map.get(c, "port", "5432")
    db = Map.get(c, "database", "laravex")
    "#{host}:#{port}/#{db}"
  end

  @impl true
  def ensure_database! do
    require_cli!("psql")
    {output, status} = run_psql("SELECT 1")

    if status != 0 do
      raise "PostgreSQL error: #{output}"
    end

    path()
  end

  @impl true
  def query(sql, bindings \\ []) do
    require_cli!("psql")
    sql = Laravex.Database.SqlBind.bind(sql, bindings)

    wrapped =
      "SELECT COALESCE(json_agg(row_to_json(_laravex_q)), '[]'::json) " <>
        "FROM (#{sql}) AS _laravex_q"

    {output, status} = run_psql(wrapped)

    if status != 0 do
      raise "PostgreSQL error: #{output}"
    end

    output = String.trim(output)

    cond do
      output == "" or output == "[]" -> []
      true -> elem(Laravex.Support.JSON.decode_array(output), 1)
    end
  end

  @impl true
  def execute(sql, bindings \\ []) do
    require_cli!("psql")
    sql = Laravex.Database.SqlBind.bind(sql, bindings)
    {output, status} = run_psql(sql)
    if status != 0, do: raise("PostgreSQL error: #{output}")
    :ok
  end

  defp cfg do
    key =
      case to_string(Laravex.Config.Repository.get("database.default", "pgsql")) do
        "postgres" -> "pgsql"
        other -> other
      end

    Laravex.Config.Repository.get("database.connections.#{key}") ||
      Laravex.Config.Repository.get("database.connections.pgsql") ||
      %{}
  end

  defp run_psql(sql) do
    c = cfg()
    host = to_string(Map.get(c, "host", "127.0.0.1"))
    port = to_string(Map.get(c, "port", "5432"))
    user = to_string(Map.get(c, "username", "root"))
    database = to_string(Map.get(c, "database", "laravex"))
    password = Map.get(c, "password") || Map.get(c, :password)

    env =
      case password do
        nil -> []
        "" -> []
        p -> [{"PGPASSWORD", to_string(p)}]
      end

    args =
      [
        "-h",
        host,
        "-p",
        port,
        "-U",
        user,
        "-d",
        database,
        "-v",
        "ON_ERROR_STOP=1",
        "-t",
        "-A"
      ] ++ ["-c", sql]

    System.cmd("psql", args, stderr_to_stdout: true, env: env)
  end

  defp require_cli!(cmd) do
    if is_nil(System.find_executable(cmd)) do
      raise "#{cmd} CLI not found. Install PostgreSQL client tools or set database.default=sqlite."
    end
  end
end
