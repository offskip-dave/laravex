defmodule Laravex.Filesystem.Disk do
  @moduledoc "Filesystem disk driver (Phase C1)."

  @callback root(cfg :: map(), name :: String.t()) :: String.t()
  @callback ensure_supported!(name :: String.t(), cfg :: map()) :: :ok
end

defmodule Laravex.Filesystem.Resolver do
  @moduledoc false

  def module(cfg) do
    driver = to_string(Map.get(cfg, "driver") || Map.get(cfg, :driver) || "local")

    case driver do
      "local" -> Laravex.Filesystem.Disks.Local
      "s3" -> Laravex.Filesystem.Disks.S3
      other ->
        raise ArgumentError,
              "Filesystem disk uses unsupported driver #{inspect(other)}. " <>
                "Supported: local, s3."
    end
  end
end
