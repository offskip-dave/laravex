defmodule Laravex.Filesystem.Storage do
  @moduledoc "Filesystem disks facade."

  def disk(name \\ nil) do
    name = name || Laravex.Config.Repository.get("filesystems.default", "local")
    disks = Laravex.Config.Repository.get("filesystems.disks", %{})
    cfg = Map.get(disks, name) || Map.get(disks, to_string(name)) || %{}
    ensure_local_driver!(name, cfg)
    root = Map.get(cfg, "root") || Map.get(cfg, :root) || storage_root(name)
    %{name: name, root: root, cfg: cfg}
  end

  defp ensure_local_driver!(name, cfg) do
    driver = Map.get(cfg, "driver") || Map.get(cfg, :driver) || "local"

    unless driver in ["local", :local] do
      raise ArgumentError,
            "Filesystem disk #{inspect(name)} uses unsupported driver #{inspect(driver)}. " <>
              "Only the \"local\" driver is available in Laravex — set FILESYSTEM_DISK=local " <>
              "(or install a cloud driver later)."
    end

    :ok
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

  @doc "Store an uploaded file; returns the relative path on the disk."
  def store(%Laravex.Http.UploadedFile{} = file, directory \\ "", disk_name \\ "public") do
    ext =
      case Laravex.Http.UploadedFile.extension(file) do
        "" -> ""
        e -> "." <> e
      end

    name = Laravex.Support.Helpers.str_random(40) <> ext
    relative = Path.join([directory, name]) |> String.trim_leading("/")
    put(relative, file.contents || "", disk_name)
    relative
  end

  def put_file(directory, %Laravex.Http.UploadedFile{} = file, disk_name \\ "public") do
    store(file, directory, disk_name)
  end

  def url(path, disk_name \\ "public") do
    d = disk(disk_name)
    base = Map.get(d.cfg, "url") || Map.get(d.cfg, :url)

    cond do
      is_binary(base) and base != "" ->
        String.trim_trailing(base, "/") <> "/" <> String.trim_leading(path, "/")

      true ->
        "/storage/" <> String.trim_leading(path, "/")
    end
  end

  def path(path, disk_name \\ nil) do
    d = disk(disk_name)
    Path.join(d.root, path)
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
