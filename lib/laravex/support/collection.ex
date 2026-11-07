defmodule Laravex.Support.Collection do
  @moduledoc "Laravel Collection subset."
  defstruct items: []

  def new(enumerable), do: %__MODULE__{items: Enum.to_list(enumerable)}

  def all(%__MODULE__{items: items}), do: items
  def count(%__MODULE__{items: items}), do: length(items)
  def first(%__MODULE__{items: [h | _]}), do: h
  def first(%__MODULE__{items: []}), do: nil
  def map(%__MODULE__{items: items}, fun), do: new(Enum.map(items, fun))
  def filter(%__MODULE__{items: items}, fun), do: new(Enum.filter(items, fun))
  def to_list(%__MODULE__{items: items}), do: items
  def pluck(%__MODULE__{items: items}, key) when is_atom(key) do
    new(Enum.map(items, fn
      %{^key => v} -> v
      map when is_map(map) -> Map.get(map, key) || Map.get(map, to_string(key))
      _ -> nil
    end))
  end
end
