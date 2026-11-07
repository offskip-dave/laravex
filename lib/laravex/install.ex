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

    IO.puts("API scaffolding installed (routes/api.ex + token auth).")
    IO.puts("Routes.Api is auto-registered on boot when the module is compiled. Run: mix compile && ./artisan migrate")
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
      @session('status')
        <p>{{ value }}</p>
      @endsession
      <form method="POST" action="/login">
        @csrf
        <label>Email <input name="email" type="email" value="{{ old('email') }}"></label>
        @error('email')<div>{{ message }}</div>@enderror
        <label>Password <input name="password" type="password"></label>
        <button type="submit">Sign in</button>
      </form>
      <p><a href="/forgot-password">Forgot password?</a></p>
    </body></html>
    """)

    File.write!(Path.join(base, "resources/views/auth/forgot_password.blade.php"), """
    <!DOCTYPE html>
    <html><head><title>Forgot Password</title></head>
    <body>
      <h1>Forgot Password</h1>
      @session('status')
        <p>{{ value }}</p>
      @endsession
      <form method="POST" action="/forgot-password">
        @csrf
        <label>Email <input name="email" type="email" value="{{ old('email') }}"></label>
        @error('email')<div>{{ message }}</div>@enderror
        <button type="submit">Email Password Reset Link</button>
      </form>
    </body></html>
    """)

    File.write!(Path.join(base, "resources/views/auth/reset_password.blade.php"), """
    <!DOCTYPE html>
    <html><head><title>Reset Password</title></head>
    <body>
      <h1>Reset Password</h1>
      <form method="POST" action="/reset-password">
        @csrf
        <input type="hidden" name="token" value="{{ token }}">
        <label>Email <input name="email" type="email" value="{{ old('email', email) }}"></label>
        <label>Password <input name="password" type="password"></label>
        <label>Confirm <input name="password_confirmation" type="password"></label>
        @error('email')<div>{{ message }}</div>@enderror
        @error('password')<div>{{ message }}</div>@enderror
        <button type="submit">Reset Password</button>
      </form>
    </body></html>
    """)

    File.write!(Path.join(base, "app/Http/Controllers/auth_controller.ex"), """
    defmodule App.Http.Controllers.AuthController do
      def show_login(_request), do: Laravex.View.make("auth/login")

      def login(request) do
        case Laravex.Auth.Guard.attempt(
               %{
                 "email" => Laravex.Http.Request.input(request, "email"),
                 "password" => Laravex.Http.Request.input(request, "password")
               },
               request
             ) do
          {:ok, _user, request} ->
            Process.put(:laravex_request, request)
            Laravex.Support.Helpers.redirect_with("/", %{"status" => "Welcome back!"})

          {:error, _} ->
            Laravex.Validation.flash_errors(request, %{"email" => ["These credentials do not match our records."]})
            |> then(fn req -> Process.put(:laravex_request, req); req end)
            raise Laravex.Validation.Failed,
              errors: %{"email" => ["These credentials do not match our records."]},
              request: Process.get(:laravex_request)
        end
      end

      def logout(request) do
        request = Laravex.Auth.Guard.logout(request)
        Process.put(:laravex_request, request)
        Laravex.Http.Response.redirect("/")
      end

      def show_forgot(_request), do: Laravex.View.make("auth/forgot_password")

      def send_reset(request) do
        email = Laravex.Http.Request.input(request, "email")
        Laravex.Validation.validate_request(request, %{"email" => "required|email"})

        case Laravex.Auth.Password.send_reset_link(%{"email" => email}) do
          :sent ->
            Laravex.Support.Helpers.redirect_with("/login", %{
              "status" => "We have emailed your password reset link."
            })

          :throttled ->
            Laravex.Support.Helpers.redirect_with("/forgot-password", %{
              "status" => "Please wait before retrying."
            })

          :user ->
            # Don't leak existence
            Laravex.Support.Helpers.redirect_with("/login", %{
              "status" => "We have emailed your password reset link."
            })
        end
      end

      def show_reset(request) do
        token = request.route_params["token"]
        email = Laravex.Http.Request.input(request, "email") || ""
        Laravex.View.make("auth/reset_password", %{token: token, email: email})
      end

      def reset(request) do
        Laravex.Validation.validate_request(request, %{
          "token" => "required",
          "email" => "required|email",
          "password" => "required|confirmed|min:8"
        })

        case Laravex.Auth.Password.reset(%{
               "email" => Laravex.Http.Request.input(request, "email"),
               "token" => Laravex.Http.Request.input(request, "token"),
               "password" => Laravex.Http.Request.input(request, "password")
             }) do
          :reset ->
            Laravex.Support.Helpers.redirect_with("/login", %{"status" => "Your password has been reset."})

          _ ->
            Laravex.Support.Helpers.redirect_with("/forgot-password", %{
              "status" => "This password reset token is invalid."
            })
        end
      end
    end
    """)

    File.write!(Path.join(base, "routes/auth.ex"), """
    defmodule Routes.Auth do
      alias Laravex.Routing.Router

      def register do
        Router.get("/login", &App.Http.Controllers.AuthController.show_login/1, name: "login")
        Router.post("/login", &App.Http.Controllers.AuthController.login/1)
        Router.post("/logout", &App.Http.Controllers.AuthController.logout/1)
        Router.get("/forgot-password", &App.Http.Controllers.AuthController.show_forgot/1, name: "password.request")
        Router.post("/forgot-password", &App.Http.Controllers.AuthController.send_reset/1, name: "password.email")
        Router.get("/reset-password/{token}", &App.Http.Controllers.AuthController.show_reset/1, name: "password.reset")
        Router.post("/reset-password", &App.Http.Controllers.AuthController.reset/1, name: "password.update")
      end
    end
    """)

    IO.puts("Starter kit installed (login, forgot/reset password, AuthController, routes/auth.ex).")
    :ok
  end
end
