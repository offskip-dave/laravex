defmodule Laravex.Database.Resolver do
  @moduledoc """
  Resolve connection name → adapter module.

  Default path is CLI / zero-Hex. When `client` is `native` (or `DB_CLIENT=native`),
  native Hex adapters (Exqlite / Postgrex / MyXQL / TDS) are used.
  """

  @supported ~w(sqlite pgsql postgres mysql mariadb sqlsrv)

  def supported, do: @supported

  def module(name \\ nil) do
    name = normalize_name(name || Laravex.Database.Connection.current_name())
    ensure_supported!(name)

    if native?(name) do
      native_module(name)
    else
      cli_module(name)
    end
  end

  def native?(name) do
    name = normalize_name(name)
    cfg = Laravex.Database.Connection.config(name)
    client = to_string(Map.get(cfg, "client") || Laravex.Env.get("DB_CLIENT", "cli"))
    client in ["native", "hex"]
  end

  def normalize_name(nil), do: normalize_name(Laravex.Config.Repository.get("database.default", "sqlite"))

  def normalize_name(name) do
    case to_string(name) do
      "postgres" -> "pgsql"
      other -> other
    end
  end

  defp ensure_supported!(name) do
    unless name in @supported do
      raise ArgumentError,
            "Database connection #{inspect(name)} is unsupported. " <>
              "Supported: #{Enum.join(@supported, ", ")}."
    end
  end

  defp cli_module("sqlite"), do: Laravex.Database.Adapters.Sqlite
  defp cli_module(name) when name in ["pgsql", "postgres"], do: Laravex.Database.Adapters.Postgres
  defp cli_module(name) when name in ["mysql", "mariadb"], do: Laravex.Database.Adapters.Mysql

  defp cli_module("sqlsrv") do
    raise ArgumentError,
          "SQL Server requires the native client (set client: \"native\" or DB_CLIENT=native)."
  end

  defp native_module("sqlite"), do: Laravex.Database.Adapters.Native.Sqlite
  defp native_module(name) when name in ["pgsql", "postgres"], do: Laravex.Database.Adapters.Native.Postgres
  defp native_module(name) when name in ["mysql", "mariadb"], do: Laravex.Database.Adapters.Native.Mysql
  defp native_module("sqlsrv"), do: Laravex.Database.Adapters.Native.SqlServer
end
