defmodule Laravex.View.Cache do
  @moduledoc "Compiled Blade source cache under storage/framework/views."

  @table :laravex_view_cache

  def ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        _ = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        :ok
      rescue
        ArgumentError -> :ok
      end
    else
      :ok
    end
  end

  def warm(base_path \\ nil) do
    ensure()
    base = base_path || Laravex.Foundation.Application.base_path()
    views_dir = Path.join(base, "resources/views")
    cache_dir = Path.join(base, "storage/framework/views")
    File.mkdir_p!(cache_dir)

    paths =
      if File.dir?(views_dir) do
        Path.wildcard(Path.join([views_dir, "**", "*.{blade.php,html,eex}"]))
      else
        []
      end

    Enum.each(paths, fn path ->
      content = File.read!(path)
      digest = :crypto.hash(:md5, path <> content) |> Base.encode16(case: :lower)
      cache_file = Path.join(cache_dir, digest <> ".blade")
      File.write!(cache_file, content)
      :ets.insert(@table, {path, %{digest: digest, content: content, cache_file: cache_file}})
    end)

    length(paths)
  end

  def clear(base_path \\ nil) do
    ensure()
    base = base_path || Laravex.Foundation.Application.base_path()
    cache_dir = Path.join(base, "storage/framework/views")

    if File.dir?(cache_dir) do
      cache_dir
      |> File.ls!()
      |> Enum.each(fn f -> File.rm(Path.join(cache_dir, f)) end)
    end

    :ets.delete_all_objects(@table)
    :ok
  end

  def read(path) do
    ensure()

    case :ets.lookup(@table, path) do
      [{^path, %{content: content}}] ->
        {:ok, content}

      [] ->
        if File.exists?(path) do
          content = File.read!(path)
          :ets.insert(@table, {path, %{content: content}})
          {:ok, content}
        else
          :error
        end
    end
  end
end
