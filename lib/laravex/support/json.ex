defmodule Laravex.Support.JSON do
  @moduledoc "Minimal JSON encode/decode without Hex deps."

  def encode!(map) when is_map(map) do
    "{" <>
      (map
       |> Enum.reject(fn {_k, v} -> is_nil(v) end)
       |> Enum.map(fn {k, v} -> ~s("#{escape(to_string(k))}":#{encode_value(v)}) end)
       |> Enum.join(",")) <> "}"
  end

  def decode(body) when is_binary(body) do
    body = String.trim(body)

    cond do
      body == "" -> {:ok, %{}}
      String.starts_with?(body, "{") -> {:ok, decode_object(body)}
      String.starts_with?(body, "[") -> decode_array(body)
      true -> {:error, :invalid}
    end
  end

  def decode_array(body) do
    body = String.trim(body)

    cond do
      body == "" ->
        {:ok, []}

      String.starts_with?(body, "[") ->
        inner = String.slice(body, 1..-2//1) |> String.trim()

        if inner == "" do
          {:ok, []}
        else
          {:ok, Enum.map(split_objects(inner), &decode_object/1)}
        end

      true ->
        {:error, :invalid}
    end
  end

  defp encode_value(nil), do: "null"
  defp encode_value(v) when is_binary(v), do: ~s("#{escape(v)}")
  defp encode_value(v) when is_boolean(v), do: to_string(v)
  defp encode_value(v) when is_atom(v), do: ~s("#{escape(Atom.to_string(v))}")
  defp encode_value(v) when is_integer(v) or is_float(v), do: to_string(v)
  defp encode_value(v) when is_list(v), do: "[" <> Enum.map_join(v, ",", &encode_value/1) <> "]"
  defp encode_value(v) when is_map(v), do: encode!(v)
  defp encode_value(v), do: ~s("#{escape(inspect(v))}")

  defp escape(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp split_objects(inner) do
    inner
    |> String.split(~r/\}\s*,\s*\{/)
    |> Enum.map(fn chunk ->
      chunk = String.trim(chunk)
      chunk = if String.starts_with?(chunk, "{"), do: chunk, else: "{" <> chunk
      if String.ends_with?(chunk, "}"), do: chunk, else: chunk <> "}"
    end)
  end

  defp decode_object(body) do
    body = String.trim(body)
    inner = String.slice(body, 1..-2//1) |> String.trim()

    if inner == "" do
      %{}
    else
      Regex.scan(~r/"([^"]+)"\s*:\s*("([^"\\]|\\.)*"|null|true|false|-?\d+(?:\.\d+)?)/, inner)
      |> Enum.map(fn
        [_, key, "null" | _] -> {key, nil}
        [_, key, "true" | _] -> {key, true}
        [_, key, "false" | _] -> {key, false}
        [_, key, val | _] ->
          if String.starts_with?(val, "\"") do
            {key, val |> String.slice(1..-2//1) |> String.replace("\\\"", "\"")}
          else
            {key, parse_num(val)}
          end
      end)
      |> Map.new()
    end
  end

  defp parse_num(n) do
    case Integer.parse(n) do
      {i, ""} -> i
      _ ->
        case Float.parse(n) do
          {f, _} -> f
          :error -> n
        end
    end
  end
end
