defmodule Laravex.Support.JSON do
  @moduledoc "JSON encode/decode via OTP :json."

  def encode!(value) do
    value
    |> normalize()
    |> :json.encode()
    |> IO.iodata_to_binary()
  end

  def decode(body) when is_binary(body) do
    body = String.trim(body)

    if body == "" do
      {:ok, %{}}
    else
      try do
        {:ok, body |> :json.decode() |> denormalize()}
      rescue
        e -> {:error, e}
      end
    end
  end

  def decode_array(body) when is_binary(body) do
    case decode(body) do
      {:ok, list} when is_list(list) -> {:ok, list}
      {:ok, other} -> {:ok, List.wrap(other)}
      error -> error
    end
  end

  defp normalize(nil), do: :null

  defp normalize(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), normalize(v)} end)
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)

  defp normalize(atom) when is_atom(atom) and atom not in [true, false, :null],
    do: Atom.to_string(atom)

  defp normalize(other), do: other

  defp denormalize(:null), do: nil
  defp denormalize(list) when is_list(list), do: Enum.map(list, &denormalize/1)

  defp denormalize(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, denormalize(v)} end)
  end

  defp denormalize(other), do: other
end
