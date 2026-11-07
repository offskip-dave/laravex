defmodule Laravex.Filesystem.Storage do
  @moduledoc "Filesystem disks facade."

  def disk(name \\ nil) do
    name = name || Laravex.Config.Repository.get("filesystems.default", "local")
    disks = Laravex.Config.Repository.get("filesystems.disks", %{})
    cfg = Map.get(disks, name) || Map.get(disks, to_string(name)) || %{}
    root = Map.get(cfg, "root") || Map.get(cfg, :root) || storage_root(name)
    %{name: name, root: root, cfg: cfg}
  end

  def put(path, contents, disk \\ nil) do
    d = disk(disk)
    full = Path.join(d.root, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, contents)
    :ok
  end

  def get(path, disk \\ nil) do
    d = disk(disk)
    File.read!(Path.join(d.root, path))
  end

  def exists?(path, disk \\ nil) do
    d = disk(disk)
    File.exists?(Path.join(d.root, path))
  end

  def delete(path, disk \\ nil) do
    d = disk(disk)
    File.rm(Path.join(d.root, path))
    :ok
  end

  def link do
    links = Laravex.Config.Repository.get("filesystems.links", %{})

    Enum.each(links, fn {link, target} ->
      File.mkdir_p!(Path.dirname(link))
      if File.exists?(link), do: File.rm_rf!(link)
      File.ln_s!(target, link)
    end)

    :ok
  end

  defp storage_root("public"),
    do: Path.join(Laravex.Foundation.Application.base_path(), "storage/app/public")

  defp storage_root(_),
    do: Path.join(Laravex.Foundation.Application.base_path(), "storage/app/private")
end
