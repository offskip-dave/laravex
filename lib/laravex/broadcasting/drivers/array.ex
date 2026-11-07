defmodule Laravex.Broadcasting.Drivers.Array do
  @moduledoc false
  @behaviour Laravex.Broadcasting.Driver

  @impl true
  def broadcast(_message), do: :ok
end
