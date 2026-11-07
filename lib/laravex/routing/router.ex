defmodule Laravex.Routing.Router do
  @moduledoc """
  Minimal Laravel-style router for the default skeleton.
  """

  @table :laravex_routes

  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table)
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    :ok
  end

  def get(path, handler) when is_binary(path) and is_function(handler, 1) do
    ensure_table()
    :ets.insert(@table, {{"GET", normalize(path)}, handler})
    :ok
  end

  def post(path, handler) when is_binary(path) and is_function(handler, 1) do
    ensure_table()
    :ets.insert(@table, {{"POST", normalize(path)}, handler})
    :ok
  end

  def dispatch(%Laravex.Http.Request{method: method, path: path} = request) do
    ensure_table()

    case :ets.lookup(@table, {method, normalize(path)}) do
      [{_, handler}] ->
        {:ok, handler.(request)}

      [] ->
        :error
    end
  end

  def routes do
    ensure_table()
    :ets.tab2list(@table)
  end

  defp normalize("/"), do: "/"
  defp normalize(path), do: path |> String.trim_trailing("/") |> then(fn p -> if p == "", do: "/", else: p end)

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      try do
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
      rescue
        ArgumentError -> :ok
      end
    end

    :ok
  end
end
