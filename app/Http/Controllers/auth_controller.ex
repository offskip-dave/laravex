defmodule App.Http.Controllers.AuthController do
  def show_login(_request), do: Laravex.View.make("auth/login")

  def login(request) do
    case Laravex.Auth.Guard.attempt(
           %{"email" => Laravex.Http.Request.input(request, "email"),
             "password" => Laravex.Http.Request.input(request, "password")},
           request
         ) do
      {:ok, _user, request} ->
        Laravex.Http.Kernel.handle(
          %{request | method: "GET", path: "/"},
          Laravex.Foundation.Application.instance()
        )
        Laravex.Http.Response.redirect("/")

      {:error, _} ->
        Laravex.Http.Response.html("Invalid credentials", 422)
    end
  end

  def logout(request) do
    _ = Laravex.Auth.Guard.logout(request)
    Laravex.Http.Response.redirect("/")
  end
end
