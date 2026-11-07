defmodule Routes.Auth do
  alias Laravex.Routing.Router

  def register do
    Router.get("/login", &App.Http.Controllers.AuthController.show_login/1, name: "login")
    Router.post("/login", &App.Http.Controllers.AuthController.login/1)
    Router.post("/logout", &App.Http.Controllers.AuthController.logout/1)
  end
end
