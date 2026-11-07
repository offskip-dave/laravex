defmodule Laravex.Http.RateLimiter do
  @moduledoc """
  Named rate limiters (Laravel RateLimiter::for).

      Laravex.Http.RateLimiter.for("api", fn _request -> [max: 60, decay: 1] end)
  """

  @table :laravex_rate_limiters

  def ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        :ets.new(@table, [:named_table, :public, :set])
      rescue
        ArgumentError -> :ok
      end
    end

    :ok
  end

  def for(name, fun) when is_function(fun, 0) or is_function(fun, 1) do
    ensure()
    :ets.insert(@table, {to_string(name), fun})
    :ok
  end

  def get(name) do
    ensure()

    case :ets.lookup(@table, to_string(name)) do
      [{_, fun}] -> fun
      [] -> nil
    end
  end

  def resolve(name, request \\ nil) do
    case get(name) do
      nil ->
        [max: 60, decay: 1]

      fun when is_function(fun, 0) ->
        normalize(fun.())

      fun when is_function(fun, 1) ->
        normalize(fun.(request))
    end
  end

  defp normalize(opts) when is_list(opts), do: opts
  defp normalize(%{max: max, decay: decay}), do: [max: max, decay: decay]
  defp normalize(%{"max" => max, "decay" => decay}), do: [max: max, decay: decay]
  defp normalize(_), do: [max: 60, decay: 1]
end
