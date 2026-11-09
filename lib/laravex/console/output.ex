defmodule Laravex.Console.Output do
  @moduledoc "ANSI helpers for Artisan (Symfony / Laravel console–style colors)."

  @doc "True when stdout is a TTY and NO_COLOR is unset."
  def color? do
    System.get_env("NO_COLOR") in [nil, ""] and IO.ANSI.enabled?()
  end

  def write(text), do: IO.write(text)
  def writeln(text \\ ""), do: IO.puts(text)

  def line(text), do: writeln(paint(text))

  def info(msg), do: badge("INFO", "blue", msg)
  def success(msg), do: badge("DONE", "green", msg)
  def comment(msg), do: line("<comment>#{msg}</comment>")
  def question(msg), do: line("<question>#{msg}</question>")
  def error(msg), do: IO.puts(:stderr, paint(" <fg=white;bg=red;options=bold> ERROR </> #{msg}"))
  def warn(msg), do: badge("WARN", "yellow", msg)

  @doc "Laravel-style section title (green bold)."
  def section(title) do
    writeln()
    line("  <fg=green;options=bold>#{title}</>")
  end

  @doc "Laravel two-column detail: label left, value right, gray dots between."
  def two_column_detail(first, second \\ nil) do
    first_s = to_string(first || "")
    second_s = if is_nil(second), do: "", else: to_string(second)
    first_plain = strip_tags(first_s)
    second_plain = strip_tags(second_s)

    cols = terminal_width()
    # indent (2) + spaces around dots (2) ≈ 4
    gap = max(cols - 4 - String.length(first_plain) - String.length(second_plain), 1)
    dots = String.duplicate(".", gap)

    line("  #{first_s} <fg=gray>#{dots}</> #{second_s}")
  end

  def green(text), do: paint("<info>#{text}</info>")
  def yellow(text), do: paint("<comment>#{text}</comment>")
  def red(text), do: paint("<error>#{text}</error>")
  def cyan(text), do: paint("<fg=cyan>#{text}</fg>")
  def bold(text), do: paint("<options=bold>#{text}</>")

  @doc "Paint Symfony-style tags: <info>, <comment>, <fg=color>, <bg=color>, <options=bold>."
  def paint(text) when is_binary(text) do
    if color?() do
      do_paint(text)
    else
      strip_tags(text)
    end
  end

  def strip_tags(text) when is_binary(text) do
    text
    |> String.replace("</>", "")
    |> then(&Regex.replace(~r/<\/?[a-zA-Z0-9_=,;-]+>/, &1, ""))
  end

  def terminal_width do
    case :io.columns() do
      {:ok, n} when is_integer(n) and n >= 40 -> n
      _ -> 80
    end
  end

  defp badge(label, color, msg) do
    line(" <fg=white;bg=#{color};options=bold> #{label} </> #{msg}")
  end

  defp do_paint(text) do
    text
    |> String.replace("<info>", IO.ANSI.green())
    |> String.replace("</info>", IO.ANSI.reset())
    |> String.replace("<comment>", IO.ANSI.yellow())
    |> String.replace("</comment>", IO.ANSI.reset())
    |> String.replace("<question>", IO.ANSI.cyan())
    |> String.replace("</question>", IO.ANSI.reset())
    |> String.replace("<error>", IO.ANSI.red() <> IO.ANSI.bright())
    |> String.replace("</error>", IO.ANSI.reset())
    |> then(fn s ->
      Regex.replace(
        ~r/<fg=([a-z]+)(?:;bg=([a-z]+))?(?:;options=([a-z]+))?>/,
        s,
        fn
          _, fg, "", "" -> ansi_fg(fg)
          _, fg, bg, "" -> ansi_fg(fg) <> ansi_bg(bg)
          _, fg, "", opts -> ansi_fg(fg) <> ansi_opts(opts)
          _, fg, bg, opts -> ansi_fg(fg) <> ansi_bg(bg) <> ansi_opts(opts)
        end
      )
    end)
    |> then(fn s ->
      Regex.replace(~r/<bg=([a-z]+)(?:;options=([a-z]+))?>/, s, fn
        _, bg, "" -> ansi_bg(bg)
        _, bg, opts -> ansi_bg(bg) <> ansi_opts(opts)
      end)
    end)
    |> then(fn s ->
      Regex.replace(~r/<options=([a-z]+)>/, s, fn _, opts -> ansi_opts(opts) end)
    end)
    |> String.replace("</>", IO.ANSI.reset())
    |> String.replace("</fg>", IO.ANSI.reset())
    |> String.replace("</bg>", IO.ANSI.reset())
  end

  defp ansi_fg("green"), do: IO.ANSI.green()
  defp ansi_fg("yellow"), do: IO.ANSI.yellow()
  defp ansi_fg("red"), do: IO.ANSI.red()
  defp ansi_fg("cyan"), do: IO.ANSI.cyan()
  defp ansi_fg("blue"), do: IO.ANSI.blue()
  defp ansi_fg("magenta"), do: IO.ANSI.magenta()
  defp ansi_fg("white"), do: IO.ANSI.white()
  defp ansi_fg("gray"), do: IO.ANSI.light_black()
  defp ansi_fg("black"), do: IO.ANSI.black()
  defp ansi_fg(_), do: ""

  defp ansi_bg("green"), do: IO.ANSI.green_background()
  defp ansi_bg("yellow"), do: IO.ANSI.yellow_background()
  defp ansi_bg("red"), do: IO.ANSI.red_background()
  defp ansi_bg("blue"), do: IO.ANSI.blue_background()
  defp ansi_bg("cyan"), do: IO.ANSI.cyan_background()
  defp ansi_bg("magenta"), do: IO.ANSI.magenta_background()
  defp ansi_bg("white"), do: IO.ANSI.white_background()
  defp ansi_bg("black"), do: IO.ANSI.black_background()
  defp ansi_bg(_), do: ""

  defp ansi_opts("bold"), do: IO.ANSI.bright()
  defp ansi_opts("bright"), do: IO.ANSI.bright()
  defp ansi_opts("underscore"), do: IO.ANSI.underline()
  defp ansi_opts(_), do: ""
end
