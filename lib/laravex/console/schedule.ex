defmodule Laravex.Console.Schedule do
  @moduledoc "Task scheduling registry (schedule:run)."

  @table :laravex_schedule

  def ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        :ets.new(@table, [:named_table, :public, :bag])
      rescue
        ArgumentError -> :ok
      end
    end

    :ok
  end

  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table)
    ensure()
  end

  def call(expression, fun, opts \\ []) when is_binary(expression) and is_function(fun, 0) do
    ensure()
    :ets.insert(@table, {:task, %{expression: expression, fun: fun, opts: opts}})
    :ok
  end

  def command(name, expression) do
    call(expression, fn -> Laravex.Console.Router.dispatch(name) end)
  end

  def run do
    ensure()
    now = :calendar.universal_time()

    :ets.lookup(@table, :task)
    |> Enum.each(fn {:task, %{expression: expr, fun: fun}} ->
      if due?(expr, now), do: fun.()
    end)

    :ok
  end

  def all do
    ensure()
    :ets.lookup(@table, :task) |> Enum.map(fn {:task, t} -> t end)
  end

  # Supports: everyMinute, hourly, daily, or cron-like "* * * * *"
  defp due?("everyMinute", _), do: true
  defp due?("hourly", {{_, _, _}, {_, m, _}}), do: m == 0
  defp due?("daily", {{_, _, _}, {h, m, _}}), do: h == 0 and m == 0
  defp due?("* * * * *", _), do: true
  defp due?(_, _), do: false
end
