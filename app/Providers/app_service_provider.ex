defmodule App.Providers.AppServiceProvider do
  @moduledoc """
  Port of app/Providers/AppServiceProvider.php
  """

  def register do
    :ok
  end

  def boot do
    Laravex.Http.RateLimiter.for("api", fn _req -> [max: 60, decay: 1] end)
    Laravex.Http.RateLimiter.for("web", fn _req -> [max: 120, decay: 1] end)
    :ok
  end
end
