defmodule Laravex.Support.Collection do
  @moduledoc "Laravel Collection subset."
  defstruct items: []

  def new(enumerable), do: %__MODULE__{items: Enum.to_list(enumerable)}

  def wrap(nil), do: new([])
  def wrap(%__MODULE__{} = c), do: c
  def wrap(list) when is_list(list), do: new(list)
  def wrap(other), do: new([other])

  def map_with_keys(%__MODULE__{items: items}, fun) when is_function(fun, 1) do
    new(
      Enum.map(items, fn item ->
        case fun.(item) do
          {k, v} -> {k, v}
          other -> other
        end
      end)
    )
  end

  def all(%__MODULE__{items: items}), do: items
  def count(%__MODULE__{items: items}), do: length(items)
  def first(%__MODULE__{items: [h | _]}), do: h
  def first(%__MODULE__{items: []}), do: nil
  def last(%__MODULE__{items: []}), do: nil
  def last(%__MODULE__{items: items}), do: List.last(items)

  @doc "Return the only item, or raise if empty/ambiguous (Laravel `sole()`)."
  def sole(%__MODULE__{items: [only]}), do: only

  def sole(%__MODULE__{items: []}) do
    raise ArgumentError, "Collection is empty (expected exactly one item)."
  end

  def sole(%__MODULE__{items: items}) do
    raise ArgumentError,
          "Collection has #{length(items)} items (expected exactly one)."
  end

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

  def keys(%__MODULE__{items: items}) do
    keys =
      if items == [] or Enum.any?(items, &match?({_, _}, &1)) do
        Enum.flat_map(items, fn
          {k, _} -> [k]
          _ -> []
        end)
      else
        Enum.with_index(items) |> Enum.map(fn {_, i} -> i end)
      end

    new(keys)
  end

  def flip(%__MODULE__{items: items}) do
    new(
      case items do
        [{_, _} | _] = pairs -> Enum.map(pairs, fn {k, v} -> {v, k} end)
        [] -> []
        list -> Enum.with_index(list) |> Enum.map(fn {v, i} -> {v, i} end)
      end
    )
  end

  def sort_keys(%__MODULE__{items: items}, desc \\ false) do
    sorted =
      if Enum.any?(items, &match?({_, _}, &1)) do
        items
        |> Enum.sort_by(fn
          {k, _} -> to_string(k)
          other -> to_string(other)
        end)
        |> then(fn s -> if desc, do: Enum.reverse(s), else: s end)
      else
        items
      end

    new(sorted)
  end

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

  def sort_by_desc(%__MODULE__{} = c, key_or_fun) do
    %__MODULE__{items: items} = sort_by(c, key_or_fun)
    new(Enum.reverse(items))
  end

  def partition(%__MODULE__{items: items}, fun) when is_function(fun, 1) do
    {pass, fail} = Enum.split_with(items, fun)
    {new(pass), new(fail)}
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

  @doc "Slice items from `start` (Laravel `slice`). Negative start counts from the end."
  def slice(%__MODULE__{items: items}, start, take_n \\ nil) when is_integer(start) do
    len = length(items)
    offset = if start < 0, do: Kernel.max(len + start, 0), else: start

    taken =
      cond do
        is_nil(take_n) -> Enum.drop(items, offset)
        is_integer(take_n) and take_n >= 0 -> Enum.slice(items, offset, take_n)
        true -> []
      end

    new(taken)
  end

  def nth(%__MODULE__{items: items}, index, default \\ nil) when is_integer(index) do
    Enum.at(items, index, default)
  end

  def get(%__MODULE__{items: items}, key, default \\ nil) do
    key_str = to_string(key)

    case Enum.find(items, fn
           {k, _} -> to_string(k) == key_str
           _ -> false
         end) do
      {_, v} ->
        v

      nil ->
        idx =
          cond do
            is_integer(key) -> key
            match?({_, ""}, Integer.parse(key_str)) ->
              {n, _} = Integer.parse(key_str)
              n

            true ->
              nil
          end

        if is_integer(idx), do: Enum.at(items, idx, default), else: default
    end
  end

  def put(%__MODULE__{items: items}, key, value) do
    key_str = to_string(key)

    cond do
      Enum.any?(items, &match?({_, _}, &1)) or items == [] ->
        case Enum.find_index(items, fn
               {k, _} -> to_string(k) == key_str
               _ -> false
             end) do
          nil -> new(items ++ [{key, value}])
          idx -> new(List.replace_at(items, idx, {key, value}))
        end

      is_integer(key) ->
        if key >= length(items) do
          new(items ++ List.duplicate(nil, key - length(items)) ++ [value])
        else
          new(List.replace_at(items, key, value))
        end

      true ->
        new(items ++ [{key, value}])
    end
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

  @doc "Alias of `unless_cond/3` (Laravel `unless`)."
  def unless(%__MODULE__{} = c, condition, fun) when is_function(fun, 1),
    do: unless_cond(c, condition, fun)

  def when_empty(%__MODULE__{} = c, fun) when is_function(fun, 1) do
    if is_empty?(c), do: fun.(c), else: c
  end

  def when_not_empty(%__MODULE__{} = c, fun) when is_function(fun, 1) do
    if is_not_empty?(c), do: fun.(c), else: c
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

  @doc "Items present in both collections (Laravel `intersect`)."
  def intersect(%__MODULE__{items: a}, %__MODULE__{items: b}), do: new(Enum.filter(a, &(&1 in b)))

  def intersect(%__MODULE__{items: a}, enumerable) do
    other = Enum.to_list(enumerable)
    new(Enum.filter(a, &(&1 in other)))
  end

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
