defmodule Database.Migrations.CreateCacheTable do
  @moduledoc """
  Port of 0001_01_01_000001_create_cache_table.php
  """

  def up do
    [
      {:create, "cache",
       [
         {:string, "key", primary: true},
         {:medium_text, "value"},
         {:big_integer, "expiration", index: true}
       ]},
      {:create, "cache_locks",
       [
         {:string, "key", primary: true},
         {:string, "owner"},
         {:big_integer, "expiration", index: true}
       ]}
    ]
    |> Laravex.Database.Migrator.apply()
  end

  def down do
    Laravex.Database.Migrator.drop(["cache", "cache_locks"])
  end
end
