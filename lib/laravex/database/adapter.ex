defmodule Laravex.Database.Adapter do
  @moduledoc """
  Database connection adapter.

  Default: CLI adapters (sqlite3 / psql / mysql).
  Optional native: Exqlite / Postgrex / MyXQL / TDS when `client: \"native\"`.
  """

  @callback path() :: String.t()
  @callback ensure_database!() :: String.t()
  @callback query(sql :: String.t(), bindings :: list()) :: list()
  @callback execute(sql :: String.t(), bindings :: list()) :: :ok
end
