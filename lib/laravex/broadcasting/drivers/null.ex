defmodule Laravex.Broadcasting.Drivers.Null do
  @moduledoc false
  @behaviour Laravex.Broadcasting.Driver

  @impl true
  def broadcast(_message), do: :ok
end
