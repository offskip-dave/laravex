defmodule Laravex.Mail.Transport do
  @moduledoc "Mail transport driver (Phase C1)."

  @callback send(message :: map()) :: :ok
end

defmodule Laravex.Mail.Resolver do
  @moduledoc false

  @supported ~w(log array smtp)

  def module(driver) when is_binary(driver) do
    unless driver in @supported do
      raise ArgumentError,
            "Mailer uses unsupported driver #{inspect(driver)}. " <>
              "Supported: #{Enum.join(@supported, ", ")}."
    end

    case driver do
      "log" -> Laravex.Mail.Transports.Log
      "array" -> Laravex.Mail.Transports.Array
      "smtp" -> Laravex.Mail.Transports.Smtp
    end
  end
end
