defmodule Laravex.Console.Router do
  @moduledoc false

  @table :laravex_console_routes

  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table)
    _ = :ets.new(@table, [:named_table, :public, :set])
    :ok
  end

  def command(name, fun) when is_binary(name) and is_function(fun, 1) do
    command(name, nil, fun)
  end

  def command(name, purpose, fun)
      when is_binary(name) and (is_binary(purpose) or is_nil(purpose)) and is_function(fun, 1) do
    ensure()
    :ets.insert(@table, {name, %{purpose: purpose, fun: fun}})
    :ok
  end

  def dispatch(name, args \\ []) do
    ensure()

    case :ets.lookup(@table, name) do
      [{^name, %{fun: fun}}] ->
        fun.(%{args: args, writeln: &IO.puts/1})
        :ok

      [] ->
        :not_found
    end
  end

  def all do
    ensure()
    :ets.tab2list(@table)
  end

  defp ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        _ = :ets.new(@table, [:named_table, :public, :set])
        :ok
      rescue
        ArgumentError -> :ok
      end
    else
      :ok
    end
  end
end
