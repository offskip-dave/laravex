defmodule Laravex.Support.Arr do
  @moduledoc "Laravel Arr helper subset."

  def get(map, key, default \\ nil) when is_map(map) do
    parts = key |> to_string() |> String.split(".")

    Enum.reduce_while(parts, map, fn part, acc ->
      cond do
        is_map(acc) and Map.has_key?(acc, part) ->
          {:cont, Map.get(acc, part)}

        is_map(acc) and Map.has_key?(acc, String.to_atom(part)) ->
          {:cont, Map.get(acc, String.to_atom(part))}

        true ->
          {:halt, default}
      end
    end)
  end

  def set(map, key, value) when is_map(map) do
    parts = key |> to_string() |> String.split(".")
    put_nested(map, parts, value)
  end

  def only(map, keys) when is_map(map) and is_list(keys) do
    key_set = MapSet.new(Enum.map(keys, &to_string/1))

    map
    |> Enum.filter(fn {k, _} -> MapSet.member?(key_set, to_string(k)) end)
    |> Map.new()
  end

  def except(map, keys) when is_map(map) and is_list(keys) do
    key_set = MapSet.new(Enum.map(keys, &to_string/1))

    map
    |> Enum.reject(fn {k, _} -> MapSet.member?(key_set, to_string(k)) end)
    |> Map.new()
  end

  def has?(map, key) when is_map(map) do
    get(map, key, :__missing__) != :__missing__
  end

  def first(list) when is_list(list), do: List.first(list)
  def last(list) when is_list(list), do: List.last(list)

  def wrap(nil), do: []
  def wrap(list) when is_list(list), do: list
  def wrap(other), do: [other]

  def flatten(list) when is_list(list), do: List.flatten(list)

  def pluck(list, key) when is_list(list) do
    Enum.map(list, fn
      map when is_map(map) -> get(map, key)
      _ -> nil
    end)
  end

  defp put_nested(map, [key], value) do
    Map.put(map, key, value)
  end

  defp put_nested(map, [key | rest], value) do
    child = Map.get(map, key) || Map.get(map, String.to_atom(key)) || %{}
    child = if is_map(child), do: child, else: %{}
    Map.put(map, key, put_nested(child, rest, value))
  end
end
