defmodule Laravex.Support.Str do
  @moduledoc "Laravel Str helper subset."
  use Laravex.Support.Macroable

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

  def contains_all?(haystack, needles) when is_list(needles),
    do: Enum.all?(needles, &contains?(haystack, &1))

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

  @doc "Take the first `n` characters (negative = from end). Laravel `Str::take`."
  def take(s, n) when is_integer(n) do
    s = to_string(s)

    cond do
      n == 0 -> ""
      n > 0 -> String.slice(s, 0, n)
      true -> String.slice(s, n, abs(n))
    end
  end

  @doc "Substring from `start` for `len` characters (Laravel `Str::substr`)."
  def substr(s, start, len \\ nil) when is_integer(start) do
    s = to_string(s)

    cond do
      is_nil(len) and start >= 0 -> String.slice(s, start..-1//1)
      is_nil(len) -> String.slice(s, start..-1//1)
      len >= 0 -> String.slice(s, start, len)
      true -> ""
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

  @doc """
  Extract a snippet around `phrase` (Laravel `Str::excerpt`).

  Options: `:radius` (default 100), `:omission` (default `"..."`).
  """
  def excerpt(s, phrase \\ "", opts \\ []) do
    s = to_string(s)
    phrase = to_string(phrase)
    radius = Keyword.get(opts, :radius, 100)
    omission = Keyword.get(opts, :omission, "...")

    cond do
      phrase == "" ->
        limit(s, radius, omission)

      true ->
        case find_index(String.downcase(s), String.downcase(phrase)) do
          nil ->
            ""

          pos ->
            len = String.length(phrase)
            start = max(pos - radius, 0)
            stop = min(pos + len + radius, String.length(s))
            snippet = String.slice(s, start, stop - start)
            left = if start > 0, do: omission, else: ""
            right = if stop < String.length(s), do: omission, else: ""
            left <> snippet <> right
        end
    end
  end

  defp find_index(haystack, needle) do
    case String.split(haystack, needle, parts: 2) do
      [left, _] -> String.length(left)
      [_] -> nil
    end
  end

  def headline(s) do
    s
    |> to_string()
    |> String.replace(~r/[_-]+/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @doc "APA-style title case (Laravel `Str::apa`)."
  def apa(s) do
    small = ~w(a an and as at but by for in nor of on or so the to up yet)

    words =
      s
      |> to_string()
      |> String.replace(~r/[_-]+/, " ")
      |> String.split(~r/\s+/, trim: true)

    last = Enum.count(words) - 1

    words
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {word, idx} ->
      lower = String.downcase(word)

      if idx > 0 and idx < last and lower in small do
        lower
      else
        String.capitalize(lower)
      end
    end)
  end

  def is_uuid?(s) when is_binary(s) do
    Regex.match?(
      ~r/\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\z/,
      s
    )
  end

  def is_uuid?(_), do: false

  def is_ulid?(s) when is_binary(s) do
    Regex.match?(~r/\A[0-9A-HJKMNP-TV-Z]{26}\z/i, s)
  end

  def is_ulid?(_), do: false

  def is_url?(s) when is_binary(s) do
    case URI.parse(s) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end

  def is_url?(_), do: false

  def is_json?(s) when is_binary(s) do
    match?({:ok, _}, Laravex.Support.JSON.decode(s))
  end

  def is_json?(_), do: false

  def is_ip?(s) when is_binary(s), do: is_ipv4?(s) or is_ipv6?(s)
  def is_ip?(_), do: false

  def is_mac_address?(s) when is_binary(s) do
    Regex.match?(~r/\A([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})\z/, s)
  end

  def is_mac_address?(_), do: false

  def is_ascii?(s) when is_binary(s), do: Regex.match?(~r/\A[\x00-\x7F]*\z/, s)
  def is_ascii?(_), do: false

  @doc "Generate a random password (Laravel `Str::password`)."
  def password(len \\ 32, opts \\ []) when is_integer(len) and len > 0 do
    letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    numbers = "0123456789"
    symbols = "!@#$%^&*()_+-=[]{}|;:,.<>?"

    alphabet =
      letters <>
        if(Keyword.get(opts, :numbers, true), do: numbers, else: "") <>
        if(Keyword.get(opts, :symbols, true), do: symbols, else: "")

    chars = String.graphemes(alphabet)
    size = Enum.count(chars)

    1..len
    |> Enum.map(fn _ -> Enum.at(chars, :rand.uniform(size) - 1) end)
    |> Enum.join()
  end

  def is_ipv4?(s) when is_binary(s) do
    match?({:ok, _}, :inet.parse_ipv4_address(String.to_charlist(s)))
  end

  def is_ipv4?(_), do: false

  def is_ipv6?(s) when is_binary(s) do
    match?({:ok, _}, :inet.parse_ipv6_address(String.to_charlist(s)))
  end

  def is_ipv6?(_), do: false

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

  @doc "Generate a Crockford Base32 ULID (Laravel `Str::ulid`)."
  def ulid do
    ms = System.system_time(:millisecond)
    <<rand::80>> = :crypto.strong_rand_bytes(10)
    encode_crockford(ms, 10) <> encode_crockford(rand, 16)
  end

  defp encode_crockford(int, len) when is_integer(int) and is_integer(len) do
    alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

    {chars, _} =
      Enum.reduce(1..len, {[], int}, fn _, {acc, n} ->
        {[String.at(alphabet, rem(n, 32)) | acc], div(n, 32)}
      end)

    Enum.join(chars)
  end

  def replace(subject, search, replace, _opts \\ []) do
    String.replace(to_string(subject), to_string(search), to_string(replace))
  end

  def replace_first(subject, search, replace) do
    String.replace(to_string(subject), to_string(search), to_string(replace), global: false)
  end

  def replace_last(subject, search, replace) do
    subject = to_string(subject)
    search = to_string(search)
    replace = to_string(replace)

    case :binary.matches(subject, search) do
      [] ->
        subject

      matches ->
        {pos, len} = List.last(matches)
        before = binary_part(subject, 0, pos)
        after_part = binary_part(subject, pos + len, byte_size(subject) - pos - len)
        before <> replace <> after_part
    end
  end

  def remove(subject, search) when is_binary(search), do: replace(subject, search, "")

  def remove(subject, searches) when is_list(searches) do
    Enum.reduce(searches, to_string(subject), fn s, acc -> replace(acc, s, "") end)
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
