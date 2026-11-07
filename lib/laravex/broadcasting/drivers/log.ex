defmodule Laravex.Broadcasting.Drivers.Log do
  @moduledoc false
  @behaviour Laravex.Broadcasting.Driver

  @impl true
  def broadcast(message) do
    Laravex.Log.Logger.info("Broadcast", message)
    :ok
  end
end
