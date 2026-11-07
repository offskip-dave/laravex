defmodule Laravex.Config.Repository do
  @moduledoc """
  Loads Laravel-style config/*.exs maps and resolves dotted keys.
  Skips Mix env files (config.exs, dev.exs, test.exs, prod.exs, runtime.exs).
  """

  @mix_config_files MapSet.new(~w(config.exs dev.exs test.exs prod.exs runtime.exs))

  @default_configs ~w(
    app auth cache database filesystems logging mail queue services session
  )

  def load!(base_path) do
    config_dir = Path.join(base_path, "config")

    files =
      if File.dir?(config_dir) do
        config_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".exs"))
        |> Enum.reject(&MapSet.member?(@mix_config_files, &1))
        |> Enum.sort()
      else
        []
      end

    # Ensure defaults are attempted even if directory listing misses them
    files =
      (@default_configs
       |> Enum.map(&"#{&1}.exs")
       |> Kernel.++(files))
      |> Enum.uniq()

    configs =
      Enum.reduce(files, %{}, fn file, acc ->
        path = Path.join(config_dir, file)
        name = Path.rootname(file)

        if File.exists?(path) do
          {value, _} = Code.eval_file(path)
          Map.put(acc, name, value)
        else
          acc
        end
      end)

    Application.put_env(:laravex, :config, configs)
    configs
  end

  def get(key, default \\ nil) when is_binary(key) do
    configs = Application.get_env(:laravex, :config, %{})
    parts = String.split(key, ".")

    case parts do
      [file | rest] ->
        deep_get(Map.get(configs, file), rest, default)

      _ ->
        default
    end
  end

  def all, do: Application.get_env(:laravex, :config, %{})

  def files do
    all() |> Map.keys() |> Enum.sort()
  end

  defp deep_get(nil, _rest, default), do: default
  defp deep_get(value, [], _default), do: value

  defp deep_get(map, [head | tail], default) when is_map(map) do
    key =
      cond do
        Map.has_key?(map, head) -> head
        Map.has_key?(map, String.to_atom(head)) -> String.to_atom(head)
        true -> nil
      end

    if key do
      deep_get(Map.get(map, key), tail, default)
    else
      default
    end
  end

  defp deep_get(_value, _rest, default), do: default
end
