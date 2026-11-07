defmodule Laravex.Filesystem.Disks.Local do
  @moduledoc false
  @behaviour Laravex.Filesystem.Disk

  @impl true
  def root(cfg, name) do
    Map.get(cfg, "root") || Map.get(cfg, :root) || default_root(name)
  end

  @impl true
  def ensure_supported!(name, cfg) do
    driver = Map.get(cfg, "driver") || Map.get(cfg, :driver) || "local"

    unless driver in ["local", :local] do
      raise ArgumentError,
            "Filesystem disk #{inspect(name)} uses unsupported driver #{inspect(driver)}. " <>
              "Only the \"local\" driver is available in Laravex — set FILESYSTEM_DISK=local " <>
              "(optional Hex cloud drivers forthcoming)."
    end

    :ok
  end

  defp default_root("public"),
    do: Path.join(Laravex.Foundation.Application.base_path(), "storage/app/public")

  defp default_root(_),
    do: Path.join(Laravex.Foundation.Application.base_path(), "storage/app/private")
end
