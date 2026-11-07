defmodule Laravex.Config.Repository do
  @moduledoc """
  Loads Laravel-style config/*.exs maps and resolves dotted keys.
  Skips Mix env files (config.exs, dev.exs, test.exs, prod.exs, runtime.exs).
  """

  @mix_config_files MapSet.new(~w(config.exs dev.exs test.exs prod.exs runtime.exs))

  @default_configs ~w(
    app auth cache database filesystems logging mail queue sanctum services session
  )

  def load!(base_path) do
    cache_path = Path.join(base_path, "bootstrap/cache/config.term")

    configs =
      if File.exists?(cache_path) do
        :erlang.binary_to_term(File.read!(cache_path))
      else
        load_from_files(base_path)
      end

    Application.put_env(:laravex, :config, configs)
    configs
  end

  def cache!(base_path \\ nil) do
    base_path = base_path || Laravex.Foundation.Application.base_path()
    configs = load_from_files(base_path)
    path = Path.join(base_path, "bootstrap/cache/config.term")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(configs))
    Application.put_env(:laravex, :config, configs)
    :ok
  end

  def clear_cache!(base_path \\ nil) do
    base_path = base_path || Laravex.Foundation.Application.base_path()
    path = Path.join(base_path, "bootstrap/cache/config.term")
    if File.exists?(path), do: File.rm!(path)
    load!(base_path)
    :ok
  end

  defp load_from_files(base_path) do
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

    files =
      (@default_configs
       |> Enum.map(&"#{&1}.exs")
       |> Kernel.++(files))
      |> Enum.uniq()

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
