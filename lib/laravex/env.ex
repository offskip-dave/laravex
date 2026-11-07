defmodule Laravex.Env do
  @moduledoc """
  Laravel-style env/2 helper backed by process dictionary / Application env / OS.
  """

  def load!(base_path) do
    path = Path.join(base_path, ".env")

    values =
      if File.exists?(path) do
        path |> File.read!() |> parse()
      else
        example = Path.join(base_path, ".env.example")

        if File.exists?(example) do
          example |> File.read!() |> parse()
        else
          %{}
        end
      end

    Application.put_env(:laravex, :env, values)
    values
  end

  def get(key, default \\ nil) when is_binary(key) do
    env = Application.get_env(:laravex, :env, %{})

    cond do
      Map.has_key?(env, key) -> coerce(env[key])
      System.get_env(key) != nil -> coerce(System.get_env(key))
      true -> default
    end
  end

  def all do
    Application.get_env(:laravex, :env, %{})
  end

  @doc "Write or replace a key in the project `.env` file and reload."
  def write!(key, value, base_path \\ nil) when is_binary(key) do
    base_path = base_path || Laravex.Foundation.Application.base_path()
    path = Path.join(base_path, ".env")
    line = "#{key}=#{value}"

    contents =
      if File.exists?(path) do
        File.read!(path)
      else
        example = Path.join(base_path, ".env.example")
        if File.exists?(example), do: File.read!(example), else: ""
      end

    updated =
      if Regex.match?(~r/^#{Regex.escape(key)}=/m, contents) do
        Regex.replace(~r/^#{Regex.escape(key)}=.*$/m, contents, line)
      else
        trim = String.trim_trailing(contents)
        if trim == "", do: line <> "\n", else: trim <> "\n" <> line <> "\n"
      end

    File.write!(path, updated)
    load!(base_path)
    :ok
  end

  defp parse(contents) do
    contents
    |> String.split(~r/\r?\n/)
    |> Enum.reduce(%{}, fn line, acc ->
      line = String.trim(line)

      cond do
        line == "" ->
          acc

        String.starts_with?(line, "#") ->
          acc

        String.contains?(line, "=") ->
          [k | rest] = String.split(line, "=", parts: 2)
          v = rest |> Enum.join("=") |> String.trim() |> strip_quotes()
          Map.put(acc, String.trim(k), v)

        true ->
          acc
      end
    end)
  end

  defp strip_quotes(value) do
    cond do
      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
        String.slice(value, 1..-2//1)

      String.starts_with?(value, "'") and String.ends_with?(value, "'") ->
        String.slice(value, 1..-2//1)

      true ->
        value
    end
  end

  defp coerce("true"), do: true
  defp coerce("false"), do: false
  defp coerce("null"), do: nil
  defp coerce("empty"), do: ""
  defp coerce(value) when is_binary(value), do: value
  defp coerce(value), do: value
end
