defmodule Bootstrap.Providers do
  @moduledoc """
  Port of bootstrap/providers.php
  """

  def list do
    [
      App.Providers.AppServiceProvider
    ]
  end
end
