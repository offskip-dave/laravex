defmodule Laravex.Log.Logger do
  @moduledoc """
  Writes to configured log channels (stack/single/daily/null).
  """

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

    case driver do
      "single" -> append_file(cfg, level, message, meta)
      "daily" -> append_file(cfg, level, message, meta)
      "monthly" -> append_file(cfg, level, message, meta)
      "stderr" -> IO.puts(:stderr, format(level, message, meta))
      "errorlog" -> IO.puts(:stderr, format(level, message, meta))
      "null" -> :ok
      _ -> append_file(cfg, level, message, meta)
    end
  end

  defp append_file(cfg, level, message, meta) do
    path =
      Map.get(cfg, "path") || Map.get(cfg, :path) ||
        Path.join(Laravex.Foundation.Application.base_path(), "storage/logs/laravex.log")

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, format(level, message, meta) <> "\n", [:append])
  end

  defp format(level, message, meta) do
    ts = DateTime.utc_now() |> DateTime.to_iso8601()
    meta_str = if map_size(meta) == 0, do: "", else: " " <> inspect(meta)
    "[#{ts}] #{level}: #{message}#{meta_str}"
  end
end
