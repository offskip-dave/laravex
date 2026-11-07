defmodule Laravex.Log.Logger do
  @moduledoc """
  Writes to configured log channels (stack/single/daily/null) with level
  filtering, placeholder replacement, and daily rotation.
  """

  @levels %{debug: 0, info: 1, notice: 2, warning: 3, error: 4, critical: 5, alert: 6, emergency: 7}

  def log(level, message, meta \\ %{}) when is_atom(level) do
    channel = Laravex.Config.Repository.get("logging.default", "stack")
    write_channel(channel, level, message, meta)
  end

  def debug(msg, meta \\ %{}), do: log(:debug, msg, meta)
  def info(msg, meta \\ %{}), do: log(:info, msg, meta)
  def warning(msg, meta \\ %{}), do: log(:warning, msg, meta)
  def error(msg, meta \\ %{}), do: log(:error, msg, meta)

  defp write_channel("stack", level, message, meta) do
    channels = Laravex.Config.Repository.get("logging.channels.stack.channels", ["single"])
    Enum.each(channels, &write_channel(&1, level, message, meta))
  end

  defp write_channel("null", _level, _message, _meta), do: :ok

  defp write_channel(name, level, message, meta) when is_binary(name) do
    cfg = Laravex.Config.Repository.get("logging.channels.#{name}", %{})
    driver = Map.get(cfg, "driver") || Map.get(cfg, :driver) || "single"
    min_level = Map.get(cfg, "level") || Map.get(cfg, :level) || "debug"

    if level_allowed?(level, min_level) do
      message = maybe_replace_placeholders(to_string(message), cfg)

      case driver do
        "single" -> append_file(cfg, level, message, meta, :single)
        "daily" -> append_file(cfg, level, message, meta, :daily)
        "monthly" -> append_file(cfg, level, message, meta, :monthly)
        "stderr" -> IO.puts(:stderr, format(level, message, meta))
        "errorlog" -> IO.puts(:stderr, format(level, message, meta))
        "null" -> :ok
        "slack" -> append_file(cfg, level, "[slack-stub] " <> message, meta, :single)
        "syslog" -> append_file(cfg, level, "[syslog-stub] " <> message, meta, :single)
        _ -> append_file(cfg, level, message, meta, :single)
      end
    else
      :ok
    end
  end

  defp level_allowed?(level, min) do
    Map.get(@levels, level, 0) >= Map.get(@levels, String.to_atom(to_string(min)), 0)
  rescue
    _ -> true
  end

  defp maybe_replace_placeholders(message, cfg) do
    replace? = Map.get(cfg, "replace_placeholders") || Map.get(cfg, :replace_placeholders)

    if replace? in [true, "true", 1, "1"] do
      message
      |> String.replace("{date}", Date.utc_today() |> Date.to_iso8601())
      |> String.replace("{env:APP_NAME}", to_string(Laravex.Env.get("APP_NAME", "Laravex")))
      |> String.replace("{env:APP_ENV}", to_string(Laravex.Env.get("APP_ENV", "local")))
    else
      message
    end
  end

  defp append_file(cfg, level, message, meta, mode) do
    base_path =
      Map.get(cfg, "path") || Map.get(cfg, :path) ||
        Path.join(Laravex.Foundation.Application.base_path(), "storage/logs/laravex.log")

    path =
      case mode do
        :daily ->
          root = String.replace_suffix(base_path, ".log", "")
          "#{root}-#{Date.utc_today() |> Date.to_iso8601()}.log"

        :monthly ->
          root = String.replace_suffix(base_path, ".log", "")
          %{year: y, month: m} = Date.utc_today()
          "#{root}-#{y}-#{String.pad_leading(Integer.to_string(m), 2, "0")}.log"

        :single ->
          base_path
      end

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, format(level, message, meta) <> "\n", [:append])

    if mode == :daily do
      rotate_daily(base_path, Map.get(cfg, "max_files") || Map.get(cfg, :max_files) || 14)
    end

    :ok
  end

  defp rotate_daily(base_path, max_files) do
    max = to_integer(max_files, 14)
    root = String.replace_suffix(base_path, ".log", "")
    dir = Path.dirname(base_path)
    prefix = Path.basename(root)

    dir
    |> File.ls!()
    |> Enum.filter(&String.starts_with?(&1, prefix <> "-"))
    |> Enum.sort()
    |> Enum.reverse()
    |> Enum.drop(max)
    |> Enum.each(fn file -> File.rm(Path.join(dir, file)) end)
  rescue
    _ -> :ok
  end

  defp to_integer(n, _) when is_integer(n), do: n

  defp to_integer(n, default) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      _ -> default
    end
  end

  defp to_integer(_, default), do: default

  defp format(level, message, meta) do
    ts = DateTime.utc_now() |> DateTime.to_iso8601()
    meta_str = if map_size(meta) == 0, do: "", else: " " <> inspect(meta)
    "[#{ts}] #{level}: #{message}#{meta_str}"
  end
end
