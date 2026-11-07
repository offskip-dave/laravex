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

  def pull(map, key, default \\ nil) when is_map(map) do
    value = get(map, key, default)
    {value, forget(map, key)}
  end

  def forget(map, key) when is_map(map) do
    parts = key |> to_string() |> String.split(".")
    delete_nested(map, parts)
  end

  def dot(map, prepend \\ "") when is_map(map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      key = if prepend == "", do: to_string(k), else: prepend <> "." <> to_string(k)

      cond do
        is_map(v) and map_size(v) > 0 ->
          Map.merge(acc, dot(v, key))

        true ->
          Map.put(acc, key, v)
      end
    end)
  end

  def collapse(list) when is_list(list) do
    Enum.flat_map(list, fn
      l when is_list(l) -> l
      other -> [other]
    end)
  end

  def where(list, fun) when is_list(list) and is_function(fun, 1) do
    Enum.filter(list, fun)
  end

  def where(list, key, value) when is_list(list) do
    Enum.filter(list, fn
      map when is_map(map) -> get(map, key) == value
      _ -> false
    end)
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

  @doc "Add key/value only if the key is missing."
  def add(map, key, value) when is_map(map) do
    if has?(map, key), do: map, else: set(map, key, value)
  end

  def prepend(list, value) when is_list(list), do: [value | list]

  def prepend(map, key, value) when is_map(map) do
    existing = get(map, key, [])
    existing = if is_list(existing), do: existing, else: [existing]
    set(map, key, [value | existing])
  end

  @doc "Expand dotted keys into a nested map (inverse of `dot/1`)."
  def undot(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      set(acc, to_string(k), v)
    end)
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

  defp delete_nested(map, [key]) do
    Map.delete(map, key) |> Map.delete(safe_atom(key))
  end

  defp delete_nested(map, [key | rest]) do
    child = Map.get(map, key) || Map.get(map, safe_atom(key))

    if is_map(child) do
      Map.put(map, key, delete_nested(child, rest))
    else
      map
    end
  end

  defp safe_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end
end
