defmodule Laravex.Database.Adapter do
  @moduledoc """
  Database connection adapter (Phase C1).

  Implemented drivers: SQLite, PostgreSQL (`psql`), MySQL/MariaDB (`mysql`) CLIs.
  """

  @callback path() :: String.t()
  @callback ensure_database!() :: String.t()
  @callback query(sql :: String.t(), bindings :: list()) :: list()
  @callback execute(sql :: String.t(), bindings :: list()) :: :ok
end
