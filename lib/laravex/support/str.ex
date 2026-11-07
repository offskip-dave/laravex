defmodule Laravex.Support.Str do
  @moduledoc "Laravel Str helper subset."

  def random(n \\ 16), do: Laravex.Support.Helpers.str_random(n)

  def length(s) when is_binary(s), do: String.length(s)

  def lower(s), do: String.downcase(to_string(s))
  def upper(s), do: String.upcase(to_string(s))
  def title(s), do: s |> to_string() |> String.split() |> Enum.map_join(" ", &String.capitalize/1)

  def camel(s), do: Macro.camelize(to_string(s))
  def snake(s), do: Macro.underscore(to_string(s))
  def kebab(s), do: s |> snake() |> String.replace("_", "-")
  def studly(s), do: camel(s)

  def contains?(haystack, needle) when is_binary(needle),
    do: String.contains?(to_string(haystack), needle)

  def contains?(haystack, needles) when is_list(needles),
    do: Enum.any?(needles, &contains?(haystack, &1))

  def starts_with?(s, prefix), do: String.starts_with?(to_string(s), prefix)
  def ends_with?(s, suffix), do: String.ends_with?(to_string(s), suffix)

  def limit(s, max, ending \\ "...") do
    s = to_string(s)

    if String.length(s) <= max do
      s
    else
      String.slice(s, 0, max) <> ending
    end
  end

  def slug(s, sep \\ "-") do
    s
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, sep)
    |> String.trim(sep)
  end

  def finish(s, cap) do
    s = to_string(s)
    if String.ends_with?(s, cap), do: s, else: s <> cap
  end

  def before(s, search) do
    case String.split(to_string(s), search, parts: 2) do
      [left, _] -> left
      [only] -> only
    end
  end

  def after_value(s, search) do
    case String.split(to_string(s), search, parts: 2) do
      [_, right] -> right
      [_] -> ""
    end
  end
end
