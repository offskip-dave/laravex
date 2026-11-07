defmodule App.Http.Controllers.AuthController do
  def show_login(request) do
    # Ensure CSRF token is available in the view assigns
    token = Map.get(request.session, "_token")
    Laravex.View.make("auth/login", %{"_token" => token, "csrf_token" => token})
  end

  def login(request) do
    case Laravex.Auth.Guard.attempt(
           %{
             "email" => Laravex.Http.Request.input(request, "email"),
             "password" => Laravex.Http.Request.input(request, "password")
           },
           request
         ) do
      {:ok, _user, request} ->
        Laravex.Http.Kernel.persist_session(request, Laravex.Http.Response.redirect("/"))

      {:error, _} ->
        Laravex.Http.Response.html("Invalid credentials", 422)
    end
  end

  def logout(request) do
    request = Laravex.Auth.Guard.logout(request)
    Laravex.Http.Kernel.persist_session(request, Laravex.Http.Response.redirect("/"))
  end
end
