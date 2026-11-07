defmodule Laravex.Support.Str do
  @moduledoc "Laravel Str helper subset."

  import Kernel, except: [length: 1]

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

  def start(s, prefix) do
    s = to_string(s)
    if String.starts_with?(s, prefix), do: s, else: prefix <> s
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

  def before_last(s, search) do
    s = to_string(s)

    case :binary.matches(s, search) |> List.last() do
      {pos, _} -> binary_part(s, 0, pos)
      nil -> s
    end
  end

  def after_last(s, search) do
    s = to_string(s)

    case :binary.matches(s, search) |> List.last() do
      {pos, len} -> binary_part(s, pos + len, byte_size(s) - pos - len)
      nil -> ""
    end
  end

  def between(s, from, to) do
    s |> after_value(from) |> before(to)
  end

  def words(s, words \\ 100, ending \\ "...") do
    parts = s |> to_string() |> String.split(~r/\s+/, trim: true)

    if Enum.count(parts) <= words do
      Enum.join(parts, " ")
    else
      parts |> Enum.take(words) |> Enum.join(" ") |> Kernel.<>(ending)
    end
  end

  def headline(s) do
    s
    |> to_string()
    |> String.replace(~r/[_-]+/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  def is_uuid?(s) when is_binary(s) do
    Regex.match?(
      ~r/\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\z/,
      s
    )
  end

  def is_uuid?(_), do: false

  def squish(s) do
    s
    |> to_string()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  def uuid do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    c = Bitwise.bor(Bitwise.band(c, 0x0FFF), 0x4000)
    d = Bitwise.bor(Bitwise.band(d, 0x3FFF), 0x8000)

    :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [a, b, c, d, e])
    |> IO.iodata_to_binary()
  end

  def replace(subject, search, replace, _opts \\ []) do
    String.replace(to_string(subject), to_string(search), to_string(replace))
  end

  def mask(s, character \\ "*", index \\ 0, length \\ nil) do
    s = to_string(s)
    len = String.length(s)
    index = max(index, 0)
    length = length || max(len - index, 0)
    length = min(length, len - index)

    prefix = String.slice(s, 0, index)
    masked = String.duplicate(to_string(character), length)
    suffix = String.slice(s, index + length, len)
    prefix <> masked <> suffix
  end
end
