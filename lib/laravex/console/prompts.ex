defmodule Laravex.Console.Prompts do
  @moduledoc "Laravel Prompts lite for Artisan (IO wrappers)."

  def text(label, opts \\ []) do
    default = Keyword.get(opts, :default, "")
    IO.write("#{label}#{if default != "", do: " [#{default}]", else: ""}: ")
    line = IO.gets("") |> to_string() |> String.trim()
    if line == "", do: default, else: line
  end

  def confirm(label, opts \\ []) do
    default = Keyword.get(opts, :default, false)
    hint = if default, do: "Y/n", else: "y/N"
    IO.write("#{label} (#{hint}): ")
    line = IO.gets("") |> to_string() |> String.trim() |> String.downcase()

    cond do
      line in ["y", "yes"] -> true
      line in ["n", "no"] -> false
      line == "" -> default
      true -> default
    end
  end

  def select(label, options) when is_list(options) do
    IO.puts(label)

    options
    |> Enum.with_index(1)
    |> Enum.each(fn {opt, i} -> IO.puts("  #{i}) #{opt}") end)

    IO.write("Choice: ")
    line = IO.gets("") |> to_string() |> String.trim()

    case Integer.parse(line) do
      {n, _} when n >= 1 and n <= length(options) -> Enum.at(options, n - 1)
      _ -> List.first(options)
    end
  end

  def password(label) do
    # Echo is not disabled in plain Mix IO; treat as text for now.
    text(label)
  end

  def info(msg), do: IO.puts(msg)
  def error(msg), do: IO.puts(:stderr, msg)
  def warn(msg), do: IO.puts("WARN: #{msg}")
end
