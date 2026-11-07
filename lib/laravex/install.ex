defmodule Laravex.Install do
  @moduledoc "install:* commands for optional Laravel-like features."

  def api do
    base = Laravex.Foundation.Application.base_path()

    File.write!(Path.join(base, "routes/api.ex"), """
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
    """)

    # Wire into bootstrap if not present
    boot = Path.join(base, "bootstrap/app.ex")
    contents = File.read!(boot)

    unless String.contains?(contents, "Routes.Api") do
      IO.puts("API routes file created at routes/api.ex — register Routes.Api in bootstrap if needed.")
    end

    IO.puts("API scaffolding installed (routes/api.ex + token auth).")
    :ok
  end

  def broadcasting do
    base = Laravex.Foundation.Application.base_path()

    File.write!(Path.join(base, "routes/channels.ex"), """
    defmodule Routes.Channels do
      def register do
        # Broadcast channel authorization callbacks
        :ok
      end
    end
    """)

    File.write!(Path.join(base, "config/broadcasting.exs"), """
    %{
      "default" => Laravex.Env.get("BROADCAST_CONNECTION", "log"),
      "connections" => %{
        "log" => %{"driver" => "log"},
        "null" => %{"driver" => "null"},
        "reverb" => %{"driver" => "reverb"},
        "pusher" => %{"driver" => "pusher"},
        "ably" => %{"driver" => "ably"}
      }
    }
    """)

    IO.puts("Broadcasting scaffolding installed.")
    :ok
  end

  def starter_kit do
    base = Laravex.Foundation.Application.base_path()

    File.mkdir_p!(Path.join(base, "resources/views/auth"))

    File.write!(Path.join(base, "resources/views/auth/login.blade.php"), """
    <!DOCTYPE html>
    <html><head><title>Login</title></head>
    <body>
      <h1>Login</h1>
      <form method="POST" action="/login">
        @csrf
        <label>Email <input name="email" type="email"></label>
        <label>Password <input name="password" type="password"></label>
        <button type="submit">Sign in</button>
      </form>
    </body></html>
    """)

    File.write!(Path.join(base, "app/Http/Controllers/auth_controller.ex"), """
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
    """)

    # Append auth routes helper file
    File.write!(Path.join(base, "routes/auth.ex"), """
    defmodule Routes.Auth do
      alias Laravex.Routing.Router

      def register do
        Router.get("/login", &App.Http.Controllers.AuthController.show_login/1, name: "login")
        Router.post("/login", &App.Http.Controllers.AuthController.login/1)
        Router.post("/logout", &App.Http.Controllers.AuthController.logout/1)
      end
    end
    """)

    IO.puts("Starter kit installed (login view, AuthController, routes/auth.ex).")
    :ok
  end
end
