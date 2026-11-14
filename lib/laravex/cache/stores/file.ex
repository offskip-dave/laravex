defmodule Laravex.Cache.Stores.File do
  @moduledoc false
  @behaviour Laravex.Cache.Store

  @impl true
  def get(key, %{array: array}), do: read_file(key) || Map.get(array, key)

  @impl true
  def put(key, entry, _state) do
    write_file(key, entry)
    :ok
  end

  @impl true
  def forget(key) do
    path = Path.join(data_path(), Base.encode16(key))
    _ = if File.exists?(path), do: File.rm(path)
    :ok
  end

  @impl true
  def flush, do: :ok

  @doc "Directory for file-cache lock files (separate from data; Laravel #6871)."
  def lock_path do
    cfg = Laravex.Config.Repository.get("cache.stores.file.lock_path")

    cond do
      is_binary(cfg) and cfg != "" -> cfg
      true ->
        Path.join(Laravex.Foundation.Application.base_path(), "storage/framework/cache/locks")
    end
  end

  defp data_path do
    cfg = Laravex.Config.Repository.get("cache.stores.file.path")

    cond do
      is_binary(cfg) and cfg != "" -> cfg
      true ->
        Path.join(Laravex.Foundation.Application.base_path(), "storage/framework/cache/data")
    end
  end

  defp write_file(key, entry) do
    dir = data_path()
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, Base.encode16(key)), :erlang.term_to_binary(entry))
  end

  defp read_file(key) do
    path = Path.join(data_path(), Base.encode16(key))
    if File.exists?(path), do: :erlang.binary_to_term(File.read!(path)), else: nil
  end
end
