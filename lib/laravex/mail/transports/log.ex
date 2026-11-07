defmodule Laravex.Mail.Transports.Log do
  @moduledoc false
  @behaviour Laravex.Mail.Transport

  @impl true
  def send(message) do
    Laravex.Log.Logger.info("Mail sent", message)
    :ok
  end
end
