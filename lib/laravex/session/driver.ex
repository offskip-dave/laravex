defmodule Laravex.Session.Driver do
  @moduledoc """
  Session persistence driver (Phase C1). Request-local ETS cache stays in `Laravex.Session.Store`.
  """

  @callback read(sid :: String.t()) :: {:ok, map()} | :error
  @callback write(sid :: String.t(), session :: map()) :: :ok
  @callback delete(sid :: String.t()) :: :ok
  @callback gc_expired(cutoff :: integer()) :: :ok
end

defmodule Laravex.Session.Resolver do
  @moduledoc false

  @supported ~w(file database redis)

  def module do
    driver = to_string(Laravex.Config.Repository.get("session.driver", "file"))

    unless driver in @supported do
      raise ArgumentError,
            "Session uses unsupported driver #{inspect(driver)}. " <>
              "Supported: #{Enum.join(@supported, ", ")}."
    end

    case driver do
      "file" -> Laravex.Session.Drivers.File
      "database" -> Laravex.Session.Drivers.Database
      "redis" -> Laravex.Session.Drivers.Redis
    end
  end
end
