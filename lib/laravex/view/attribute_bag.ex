defmodule Laravex.View.AttributeBag do
  @moduledoc """
  Blade component attribute bag with escaping (Laravel ComponentAttributeBag).

  Defaults are escaped unless marked as `{:raw, value}` (AppendableAttributeValue stand-in).
  """

  defstruct attributes: %{}

  def new(attrs \\ %{}) when is_map(attrs) do
    %__MODULE__{attributes: stringify(attrs)}
  end

  def merge(%__MODULE__{} = bag, defaults, _escape \\ true) when is_map(defaults) do
    # Store raw values; `to_html/1` always escapes on render (avoids double-escape).
    # `{:raw, value}` opts out of escaping at render time.
    defaults = stringify(defaults)
    %__MODULE__{attributes: Map.merge(defaults, bag.attributes)}
  end

  def get(%__MODULE__{attributes: attrs}, key, default \\ nil) do
    Map.get(attrs, to_string(key), default)
  end

  def except(%__MODULE__{attributes: attrs}, keys) do
    drop = keys |> List.wrap() |> Enum.map(&to_string/1)
    %__MODULE__{attributes: Map.drop(attrs, drop)}
  end

  def only(%__MODULE__{attributes: attrs}, keys) do
    keep = keys |> List.wrap() |> Enum.map(&to_string/1)
    %__MODULE__{attributes: Map.take(attrs, keep)}
  end

  def class(%__MODULE__{} = bag, extra) do
    existing = get(bag, "class", "")
    extras = extra |> List.wrap() |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == ""))
    merged = [existing | extras] |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
    %__MODULE__{attributes: Map.put(bag.attributes, "class", merged)}
  end

  def to_html(%__MODULE__{attributes: attrs}) do
    attrs
    |> Enum.map(fn {k, v} -> ~s(#{k}="#{render_attr(v)}") end)
    |> Enum.join(" ")
  end

  defimpl String.Chars do
    def to_string(bag), do: Laravex.View.AttributeBag.to_html(bag)
  end

  defp render_attr({:raw, value}), do: to_string(value)

  defp render_attr(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#039;")
  end

  defp stringify(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
