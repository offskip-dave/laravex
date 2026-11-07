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
    path =
      Path.join(
        Laravex.Foundation.Application.base_path(),
        "storage/framework/cache/data/#{Base.encode16(key)}"
      )

    _ = if File.exists?(path), do: File.rm(path)
    :ok
  end

  @impl true
  def flush, do: :ok

  defp write_file(key, entry) do
    dir = Path.join(Laravex.Foundation.Application.base_path(), "storage/framework/cache/data")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, Base.encode16(key)), :erlang.term_to_binary(entry))
  end

  defp read_file(key) do
    path =
      Path.join(
        Laravex.Foundation.Application.base_path(),
        "storage/framework/cache/data/#{Base.encode16(key)}"
      )

    if File.exists?(path), do: :erlang.binary_to_term(File.read!(path)), else: nil
  end
end
