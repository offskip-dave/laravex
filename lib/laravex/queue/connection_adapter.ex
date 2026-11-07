defmodule Laravex.Queue.ConnectionAdapter do
  @moduledoc """
  Queue connection adapter (Phase C1). Public API: `Laravex.Queue.Worker`.
  """

  @callback push(job_mod :: module(), args :: list(), opts :: keyword()) :: term()
end

defmodule Laravex.Queue.Resolver do
  @moduledoc false

  @supported ~w(sync database deferred redis)

  def module(connection) when is_binary(connection) do
    unless connection in @supported do
      raise ArgumentError,
            "Queue connection #{inspect(connection)} is unsupported. " <>
              "Supported: #{Enum.join(@supported, ", ")}."
    end

    case connection do
      "sync" -> Laravex.Queue.Connections.Sync
      "database" -> Laravex.Queue.Connections.Database
      "deferred" -> Laravex.Queue.Connections.Deferred
      "redis" -> Laravex.Queue.Connections.Redis
    end
  end
end
