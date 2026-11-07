defmodule Laravex.Filesystem.Storage do
  @moduledoc "Filesystem disks facade (local driver)."

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

  def put(path, contents, disk \\ nil, opts \\ []) do
    d = disk(disk)
    full = Path.join(d.root, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, contents)

    visibility =
      Keyword.get(opts, :visibility) ||
        Map.get(d.cfg, "visibility") ||
        Map.get(d.cfg, :visibility)

    apply_visibility(full, visibility)
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

  def missing?(path, disk \\ nil), do: not exists?(path, disk)

  def delete(path, disk \\ nil) do
    d = disk(disk)
    _ = File.rm(Path.join(d.root, path))
    :ok
  end

  def size(path, disk \\ nil) do
    d = disk(disk)
    case File.stat(Path.join(d.root, path)) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end

  @doc "Last modification unix timestamp, or nil if missing (Laravel `lastModified`)."
  def last_modified(path, disk \\ nil) do
    d = disk(disk)

    case File.stat(Path.join(d.root, path)) do
      {:ok, %{mtime: {{_, _, _}, {_, _, _}} = erl}} ->
        erl
        |> NaiveDateTime.from_erl!()
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_unix()

      {:ok, %{mtime: %NaiveDateTime{} = ndt}} ->
        DateTime.from_naive!(ndt, "Etc/UTC") |> DateTime.to_unix()

      {:ok, %{mtime: %DateTime{} = dt}} ->
        DateTime.to_unix(dt)

      {:ok, %{mtime: n}} when is_integer(n) ->
        n

      _ ->
        nil
    end
  end

  def copy(from, to, disk \\ nil) do
    d = disk(disk)
    src = Path.join(d.root, from)
    dest = Path.join(d.root, to)
    File.mkdir_p!(Path.dirname(dest))
    File.cp!(src, dest)
    :ok
  end

  def move(from, to, disk \\ nil) do
    d = disk(disk)
    src = Path.join(d.root, from)
    dest = Path.join(d.root, to)
    File.mkdir_p!(Path.dirname(dest))
    case File.rename(src, dest) do
      :ok -> :ok
      {:error, reason} -> raise File.Error, reason: reason, action: "rename", path: src
    end
  end

  def files(directory, disk \\ nil) do
    d = disk(disk)
    dir = Path.join(d.root, directory)

    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn name -> File.regular?(Path.join(dir, name)) end)
        |> Enum.map(fn name -> Path.join(directory, name) |> String.trim_leading("/") end)

      _ ->
        []
    end
  end

  @doc "Recursively list files under a directory (Laravel `allFiles`)."
  def all_files(directory, disk \\ nil) do
    d = disk(disk)
    abs = Path.join(d.root, directory)
    collect_files(abs, directory)
  end

  defp collect_files(abs, relative) do
    case File.ls(abs) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn name ->
          full = Path.join(abs, name)
          rel = Path.join(relative, name) |> String.trim_leading("/")

          cond do
            File.regular?(full) -> [rel]
            File.dir?(full) -> collect_files(full, rel)
            true -> []
          end
        end)

      _ ->
        []
    end
  end

  def delete_directory(directory, disk \\ nil) do
    d = disk(disk)
    _ = File.rm_rf(Path.join(d.root, directory))
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

  @doc "Store an uploaded file under a given name (Laravel `putFileAs`)."
  def put_file_as(directory, %Laravex.Http.UploadedFile{} = file, name, disk_name \\ "public")
      when is_binary(name) do
    ext =
      case Laravex.Http.UploadedFile.extension(file) do
        "" -> ""
        e -> "." <> e
      end

    basename =
      if Path.extname(name) == "" and ext != "", do: name <> ext, else: name

    relative = Path.join([directory, basename]) |> String.trim_leading("/")
    put(relative, file.contents || "", disk_name)
    relative
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

  @doc """
  Temporary signed URL for a stored path (Laravel `Storage::temporaryUrl`).

  `expiration` may be seconds from now, a unix timestamp, or a `DateTime`.
  """
  def temporary_url(path, expiration, opts \\ []) do
    disk_name = Keyword.get(opts, :disk, "public")
    absolute = url(path, disk_name)
    uri = URI.parse(absolute)
    signed_path = uri.path || absolute

    seconds =
      case expiration do
        %DateTime{} = dt ->
          max(DateTime.to_unix(dt) - System.system_time(:second), 0)

        n when is_integer(n) and n > 1_000_000_000 ->
          max(n - System.system_time(:second), 0)

        n when is_integer(n) ->
          n
      end

    signed = Laravex.Http.UrlSigner.temporary(signed_path, seconds)

    case uri do
      %URI{scheme: scheme, host: host} when is_binary(scheme) and is_binary(host) ->
        port =
          cond do
            is_nil(uri.port) -> ""
            scheme == "http" and uri.port == 80 -> ""
            scheme == "https" and uri.port == 443 -> ""
            true -> ":#{uri.port}"
          end

        "#{scheme}://#{host}#{port}#{signed}"

      _ ->
        signed
    end
  end

  def path(path, disk_name \\ nil) do
    d = disk(disk_name)
    Path.join(d.root, path)
  end

  def download(path, opts \\ []) do
    disk_name = Keyword.get(opts, :disk)
    filename = Keyword.get(opts, :as) || Path.basename(path)
    contents = get(path, disk_name)
    Laravex.Http.Response.download(contents, filename, opts)
  end

  def link do
    links = Laravex.Config.Repository.get("filesystems.links", %{})

    Enum.each(links, fn {link, target} ->
      File.mkdir_p!(Path.dirname(link))
      _ = if File.exists?(link), do: File.rm_rf!(link)
      File.ln_s!(target, link)
    end)

    :ok
  end

  defp apply_visibility(_full, nil), do: :ok
  defp apply_visibility(_full, "public"), do: :ok
  defp apply_visibility(full, :public), do: apply_visibility(full, "public")

  defp apply_visibility(full, "private") do
    # Best-effort local permission bit (ignored on some platforms / sandboxes)
    _ = File.chmod(full, 0o600)
    :ok
  rescue
    _ -> :ok
  end

  defp apply_visibility(full, :private), do: apply_visibility(full, "private")
  defp apply_visibility(_, _), do: :ok

  defp storage_root("public"),
    do: Path.join(Laravex.Foundation.Application.base_path(), "storage/app/public")

  defp storage_root(_),
    do: Path.join(Laravex.Foundation.Application.base_path(), "storage/app/private")
end
