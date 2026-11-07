defmodule Laravex.Support.Collection do
  @moduledoc "Laravel Collection subset."
  defstruct items: []

  def new(enumerable), do: %__MODULE__{items: Enum.to_list(enumerable)}

  def all(%__MODULE__{items: items}), do: items
  def count(%__MODULE__{items: items}), do: length(items)
  def first(%__MODULE__{items: [h | _]}), do: h
  def first(%__MODULE__{items: []}), do: nil
  def last(%__MODULE__{items: []}), do: nil
  def last(%__MODULE__{items: items}), do: List.last(items)

  def map(%__MODULE__{items: items}, fun), do: new(Enum.map(items, fun))
  def filter(%__MODULE__{items: items}, fun), do: new(Enum.filter(items, fun))
  def reject(%__MODULE__{items: items}, fun), do: new(Enum.reject(items, fun))
  def each(%__MODULE__{items: items} = c, fun) do
    Enum.each(items, fun)
    c
  end

  def reduce(%__MODULE__{items: items}, acc, fun), do: Enum.reduce(items, acc, fun)
  def to_list(%__MODULE__{items: items}), do: items
  def values(%__MODULE__{items: items}), do: new(Enum.map(items, fn {_k, v} -> v; v -> v end))
  def is_empty?(%__MODULE__{items: []}), do: true
  def is_empty?(%__MODULE__{}), do: false
  def is_not_empty?(c), do: not is_empty?(c)

  def pluck(%__MODULE__{items: items}, key) when is_atom(key) or is_binary(key) do
    key_atom = if is_binary(key), do: String.to_atom(key), else: key
    key_str = to_string(key)

    new(
      Enum.map(items, fn
        %{^key_atom => v} -> v
        map when is_map(map) -> Map.get(map, key_atom) || Map.get(map, key_str)
        _ -> nil
      end)
    )
  end

  def where(%__MODULE__{items: items}, key, value) do
    key_atom = if is_binary(key), do: String.to_atom(key), else: key
    key_str = to_string(key)

    new(
      Enum.filter(items, fn
        map when is_map(map) ->
          Map.get(map, key_atom) == value or Map.get(map, key_str) == value

        _ ->
          false
      end)
    )
  end

  def where(%__MODULE__{items: items}, fun) when is_function(fun, 1) do
    new(Enum.filter(items, fun))
  end

  def group_by(%__MODULE__{items: items}, key) when is_atom(key) or is_binary(key) do
    key_atom = if is_binary(key), do: String.to_atom(key), else: key
    key_str = to_string(key)

    items
    |> Enum.group_by(fn
      map when is_map(map) -> Map.get(map, key_atom) || Map.get(map, key_str)
      _ -> nil
    end)
    |> Map.new(fn {k, v} -> {k, new(v)} end)
  end

  def group_by(%__MODULE__{items: items}, fun) when is_function(fun, 1) do
    items
    |> Enum.group_by(fun)
    |> Map.new(fn {k, v} -> {k, new(v)} end)
  end

  def key_by(%__MODULE__{items: items}, key) when is_atom(key) or is_binary(key) do
    key_atom = if is_binary(key), do: String.to_atom(key), else: key
    key_str = to_string(key)

    Map.new(items, fn
      map when is_map(map) ->
        {(Map.get(map, key_atom) || Map.get(map, key_str)), map}

      other ->
        {nil, other}
    end)
  end

  def sum(%__MODULE__{items: items}) do
    Enum.reduce(items, 0, fn
      n, acc when is_number(n) -> acc + n
      _, acc -> acc
    end)
  end

  def sum(%__MODULE__{} = c, key) do
    c |> pluck(key) |> sum()
  end

  def sort_by(%__MODULE__{items: items}, key) when is_atom(key) or is_binary(key) do
    key_atom = if is_binary(key), do: String.to_atom(key), else: key
    key_str = to_string(key)

    new(
      Enum.sort_by(items, fn
        map when is_map(map) -> Map.get(map, key_atom) || Map.get(map, key_str)
        other -> other
      end)
    )
  end

  def sort_by(%__MODULE__{items: items}, fun) when is_function(fun, 1) do
    new(Enum.sort_by(items, fun))
  end

  def first_where(%__MODULE__{} = c, key, value) do
    c |> where(key, value) |> first()
  end

  def first_where(%__MODULE__{items: items}, fun) when is_function(fun, 1) do
    Enum.find(items, fun)
  end

  def flat_map(%__MODULE__{items: items}, fun) when is_function(fun, 1) do
    new(
      Enum.flat_map(items, fn item ->
        case fun.(item) do
          %__MODULE__{items: nested} -> nested
          list when is_list(list) -> list
          other -> [other]
        end
      end)
    )
  end

  def only(%__MODULE__{items: items}, keys) when is_list(keys) do
    key_set = MapSet.new(Enum.map(keys, &to_string/1))

    new(
      Enum.map(items, fn
        map when is_map(map) ->
          map
          |> Enum.filter(fn {k, _} -> MapSet.member?(key_set, to_string(k)) end)
          |> Map.new()

        other ->
          other
      end)
    )
  end

  def except(%__MODULE__{items: items}, keys) when is_list(keys) do
    key_set = MapSet.new(Enum.map(keys, &to_string/1))

    new(
      Enum.map(items, fn
        map when is_map(map) ->
          map
          |> Enum.reject(fn {k, _} -> MapSet.member?(key_set, to_string(k)) end)
          |> Map.new()

        other ->
          other
      end)
    )
  end

  def take(%__MODULE__{items: items}, n) when is_integer(n) and n >= 0 do
    new(Enum.take(items, n))
  end

  def skip(%__MODULE__{items: items}, n) when is_integer(n) and n >= 0 do
    new(Enum.drop(items, n))
  end

  def reverse(%__MODULE__{items: items}), do: new(Enum.reverse(items))

  def contains?(%__MODULE__{items: items}, fun) when is_function(fun, 1) do
    Enum.any?(items, fun)
  end

  def contains?(%__MODULE__{items: items}, value) do
    value in items
  end

  def contains?(%__MODULE__{} = c, key, value) do
    c |> where(key, value) |> is_not_empty?()
  end

  def unique(%__MODULE__{items: items}), do: new(Enum.uniq(items))

  def unique(%__MODULE__{items: items}, key) when is_atom(key) or is_binary(key) do
    key_atom = if is_binary(key), do: String.to_atom(key), else: key
    key_str = to_string(key)

    new(
      Enum.uniq_by(items, fn
        map when is_map(map) -> Map.get(map, key_atom) || Map.get(map, key_str)
        other -> other
      end)
    )
  end

  def unique(%__MODULE__{items: items}, fun) when is_function(fun, 1) do
    new(Enum.uniq_by(items, fun))
  end

  def merge(%__MODULE__{items: a}, %__MODULE__{items: b}), do: new(a ++ b)
  def merge(%__MODULE__{items: a}, enumerable), do: new(a ++ Enum.to_list(enumerable))

  def concat(%__MODULE__{} = c, other), do: merge(c, other)

  def implode(%__MODULE__{items: items}, glue \\ "") do
    items
    |> Enum.map(&to_string/1)
    |> Enum.join(glue)
  end

  def when_cond(%__MODULE__{} = c, condition, fun) when is_function(fun, 1) do
    if truthy?(condition), do: fun.(c), else: c
  end

  def unless_cond(%__MODULE__{} = c, condition, fun) when is_function(fun, 1) do
    if truthy?(condition), do: c, else: fun.(c)
  end

  def avg(%__MODULE__{items: []}), do: nil

  def avg(%__MODULE__{items: items}) do
    nums = Enum.filter(items, &is_number/1)
    if nums == [], do: nil, else: Enum.sum(nums) / length(nums)
  end

  def avg(%__MODULE__{} = c, key), do: c |> pluck(key) |> avg()
  def average(c), do: avg(c)
  def average(c, key), do: avg(c, key)

  def min(%__MODULE__{items: []}), do: nil
  def min(%__MODULE__{items: items}), do: Enum.min(Enum.filter(items, &is_number/1), fn -> nil end)
  def min(%__MODULE__{} = c, key), do: c |> pluck(key) |> min()

  def max(%__MODULE__{items: []}), do: nil
  def max(%__MODULE__{items: items}), do: Enum.max(Enum.filter(items, &is_number/1), fn -> nil end)
  def max(%__MODULE__{} = c, key), do: c |> pluck(key) |> max()

  def chunk(%__MODULE__{items: items}, size) when is_integer(size) and size > 0 do
    new(Enum.chunk_every(items, size) |> Enum.map(&new/1))
  end

  def flatten(%__MODULE__{items: items}) do
    new(
      Enum.flat_map(items, fn
        %__MODULE__{items: nested} -> nested
        list when is_list(list) -> list
        other -> [other]
      end)
    )
  end

  def diff(%__MODULE__{items: a}, %__MODULE__{items: b}), do: new(a -- b)
  def diff(%__MODULE__{items: a}, enumerable), do: new(a -- Enum.to_list(enumerable))

  def pipe(%__MODULE__{} = c, fun) when is_function(fun, 1), do: fun.(c)

  def tap(%__MODULE__{} = c, fun) when is_function(fun, 1) do
    fun.(c)
    c
  end

  def shuffle(%__MODULE__{items: items}), do: new(Enum.shuffle(items))

  def random(%__MODULE__{items: []}), do: nil
  def random(%__MODULE__{items: items}), do: Enum.random(items)

  def random(%__MODULE__{items: items}, n) when is_integer(n) and n >= 0 do
    new(items |> Enum.shuffle() |> Enum.take(n))
  end

  def pad(%__MODULE__{items: items}, size, value \\ nil) when is_integer(size) do
    abs_size = abs(size)
    current = length(items)

    cond do
      current >= abs_size ->
        new(Enum.take(items, abs_size))

      size >= 0 ->
        new(items ++ List.duplicate(value, abs_size - current))

      true ->
        new(List.duplicate(value, abs_size - current) ++ items)
    end
  end

  @doc "Cartesian product with another list/collection (Laravel `crossJoin`)."
  def cross_join(%__MODULE__{items: items}, other) do
    other_items =
      case other do
        %__MODULE__{items: o} -> o
        enumerable -> Enum.to_list(enumerable)
      end

    new(
      for a <- items, b <- other_items do
        List.wrap(a) ++ List.wrap(b)
      end
    )
  end

  @doc "Sliding windows of `size` (Laravel `sliding`). Optional step defaults to 1."
  def sliding(%__MODULE__{items: items}, size, step \\ 1)
      when is_integer(size) and size > 0 and is_integer(step) and step > 0 do
    new(
      items
      |> Enum.chunk_every(size, step, :discard)
      |> Enum.map(&new/1)
    )
  end

  defp truthy?(v) when v in [false, nil, 0, "", "0"], do: false
  defp truthy?(_), do: true

  def to_map(%__MODULE__{items: items}) do
    case items do
      [{_, _} | _] -> Map.new(items)
      _ -> Enum.with_index(items) |> Map.new(fn {v, i} -> {i, v} end)
    end
  end
end
