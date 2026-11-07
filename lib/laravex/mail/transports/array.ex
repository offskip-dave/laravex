defmodule Laravex.Mail.Transports.Array do
  @moduledoc false
  @behaviour Laravex.Mail.Transport

  @impl true
  def send(_message), do: :ok
end
