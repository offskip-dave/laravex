defmodule Routes.Web do
  @moduledoc """
  Port of routes/web.php
  """

  alias Laravex.Routing.Router
  alias Laravex.View

  def register do
    Router.get("/", fn _request ->
      View.make("welcome", %{
        "app_name" => Laravex.Config.Repository.get("app.name", "Laravex"),
        "version" => Application.spec(:laravex, :vsn) |> to_string(),
        "elixir" => System.version(),
        "otp" => :erlang.system_info(:otp_release) |> to_string()
      })
    end)
  end
end
