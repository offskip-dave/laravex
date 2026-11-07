defmodule Routes.Api do
  alias Laravex.Routing.Router

  def register do
    Router.group([prefix: "api", middleware: ["api"]], fn ->
      Router.get("/user", fn request ->
        user =
          case Laravex.Http.Request.bearer_token(request) do
            nil -> nil
            token -> Laravex.Auth.Token.find_user(token)
          end

        if user do
          Laravex.Http.Response.json(%{id: user.id, email: user.email, name: user.name})
        else
          Laravex.Http.Response.json(%{message: "Unauthenticated."}, 401)
        end
      end)
    end)
  end
end
