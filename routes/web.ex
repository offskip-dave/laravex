defmodule Routes.Web do
  @moduledoc """
  Port of routes/web.php
  """

  alias Laravex.Routing.Router
  alias Laravex.View

  def register do
    Router.get("/", fn _request ->
      View.make("welcome")
    end)
  end
end
