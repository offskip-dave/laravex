defmodule Laravex.Database.Adapters.Mysql do
  @moduledoc "MySQL/MariaDB via the `mysql` CLI (no Hex deps)."
  @behaviour Laravex.Database.Adapter

  @impl true
  def path do
    c = cfg()
    host = Map.get(c, "host", "127.0.0.1")
    port = Map.get(c, "port", "3306")
    db = Map.get(c, "database", "laravex")
    "#{host}:#{port}/#{db}"
  end

  @impl true
  def ensure_database! do
    require_cli!("mysql")
    {output, status} = run_mysql("SELECT 1")

    if status != 0 do
      raise "MySQL error: #{output}"
    end

    path()
  end

  @impl true
  def query(sql, bindings \\ []) do
    require_cli!("mysql")
    sql = Laravex.Database.SqlBind.bind(sql, bindings)
    {output, status} = run_mysql(sql)

    if status != 0 do
      raise "MySQL error: #{output}"
    end

    parse_batch(String.trim(output))
  end

  @impl true
  def execute(sql, bindings \\ []) do
    require_cli!("mysql")
    sql = Laravex.Database.SqlBind.bind(sql, bindings)
    {output, status} = run_mysql(sql)
    if status != 0, do: raise("MySQL error: #{output}")
    :ok
  end

  defp cfg, do: Laravex.Database.Connection.config()

  defp run_mysql(sql) do
    c = cfg()
    host = to_string(Map.get(c, "host", "127.0.0.1"))
    port = to_string(Map.get(c, "port", "3306"))
    user = to_string(Map.get(c, "username", "root"))
    database = to_string(Map.get(c, "database", "laravex"))
    password = Map.get(c, "password") || Map.get(c, :password)
    socket = Map.get(c, "unix_socket") || Map.get(c, "unix_socket")

    base =
      if is_binary(socket) and socket != "" do
        ["--protocol=socket", "-S", socket, "-u", user]
      else
        ["-h", host, "-P", port, "-u", user]
      end

    args = base ++ ["-D", database, "--batch", "--raw", "-e", sql]

    env =
      case password do
        nil -> []
        "" -> []
        p -> [{"MYSQL_PWD", to_string(p)}]
      end

    System.cmd("mysql", args, stderr_to_stdout: true, env: env)
  end

  defp parse_batch(""), do: []

  defp parse_batch(output) do
    lines = String.split(output, "\n", trim: true)

    case lines do
      [] ->
        []

      [header | rows] ->
        cols = String.split(header, "\t")

        Enum.map(rows, fn row ->
          vals = String.split(row, "\t")

          cols
          |> Enum.zip(vals)
          |> Map.new()
        end)
    end
  end

  defp require_cli!(cmd) do
    if is_nil(System.find_executable(cmd)) do
      raise "#{cmd} CLI not found. Install MySQL client tools or set database.default=sqlite."
    end
  end
end
