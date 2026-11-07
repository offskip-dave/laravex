defmodule Laravex.Database.Migrator do
  @moduledoc """
  Stub migrator that records schema operations in-memory / ETS.
  """

  @table :laravex_schema

  def apply(operations) when is_list(operations) do
    ensure()

    Enum.each(operations, fn
      {:create, name, columns} ->
        :ets.insert(@table, {name, columns})

      other ->
        :ets.insert(@table, {:op, other})
    end)

    :ok
  end

  def drop(tables) when is_list(tables) do
    ensure()
    Enum.each(tables, fn name -> :ets.delete(@table, name) end)
    :ok
  end

  def tables do
    ensure()

    :ets.tab2list(@table)
    |> Enum.filter(fn
      {name, _} when is_binary(name) -> true
      _ -> false
    end)
    |> Enum.map(fn {name, _} -> name end)
    |> Enum.sort()
  end

  def run_default_migrations do
    Database.Migrations.CreateUsersTable.up()
    Database.Migrations.CreateCacheTable.up()
    Database.Migrations.CreateJobsTable.up()
    :ok
  end

  defp ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        :ets.new(@table, [:named_table, :public, :set])
      rescue
        ArgumentError -> :ok
      end
    end

    :ok
  end
end
