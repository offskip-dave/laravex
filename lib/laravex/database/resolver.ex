defmodule Laravex.Database.Resolver do
  @moduledoc false

  @supported ~w(sqlite pgsql postgres mysql mariadb)

  def supported, do: @supported

  def module(name) when is_binary(name) or is_atom(name) do
    name = to_string(name)

    unless name in @supported do
      raise ArgumentError,
            "Database connection #{inspect(name)} is unsupported. " <>
              "Supported: #{Enum.join(@supported, ", ")}."
    end

    case name do
      "sqlite" -> Laravex.Database.Adapters.Sqlite
      "pgsql" -> Laravex.Database.Adapters.Postgres
      "postgres" -> Laravex.Database.Adapters.Postgres
      "mysql" -> Laravex.Database.Adapters.Mysql
      "mariadb" -> Laravex.Database.Adapters.Mysql
    end
  end

  def current, do: module(Laravex.Config.Repository.get("database.default", "sqlite"))
end
