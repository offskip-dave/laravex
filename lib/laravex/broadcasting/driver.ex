defmodule Laravex.Broadcasting.Driver do
  @moduledoc "Broadcast connection driver (Phase C1)."

  @callback broadcast(message :: map()) :: :ok
end

defmodule Laravex.Broadcasting.Resolver do
  @moduledoc false

  @supported ~w(log null array pubsub)

  def module(driver) when is_binary(driver) do
    unless driver in @supported do
      raise ArgumentError,
            "Broadcasting uses unsupported driver #{inspect(driver)}. " <>
              "Supported: #{Enum.join(@supported, ", ")}."
    end

    case driver do
      "log" -> Laravex.Broadcasting.Drivers.Log
      "null" -> Laravex.Broadcasting.Drivers.Null
      "array" -> Laravex.Broadcasting.Drivers.Array
      "pubsub" -> Laravex.Broadcasting.Drivers.Pubsub
    end
  end

  def current do
    to_string(Laravex.Config.Repository.get("broadcasting.default", "log"))
    |> module()
  end
end
