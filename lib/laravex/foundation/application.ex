defmodule Laravex.Foundation.Application do
  @moduledoc """
  Laravel-style application builder matching bootstrap/app.php.
  """

  defstruct base_path: nil,
            web_routes: nil,
            console_routes: nil,
            health: nil,
            middleware_callback: nil,
            exceptions_callback: nil,
            instance: nil

  def configure(opts) when is_list(opts) do
    base_path = Keyword.fetch!(opts, :base_path)
    %__MODULE__{base_path: Path.expand(base_path)}
  end

  def with_routing(%__MODULE__{} = app, opts) when is_list(opts) do
    %{
      app
      | web_routes: Keyword.get(opts, :web),
        console_routes: Keyword.get(opts, :commands),
        health: Keyword.get(opts, :health)
    }
  end

  def with_middleware(%__MODULE__{} = app, callback) when is_function(callback, 1) do
    %{app | middleware_callback: callback}
  end

  def with_exceptions(%__MODULE__{} = app, callback) when is_function(callback, 1) do
    %{app | exceptions_callback: callback}
  end

  def create(%__MODULE__{} = app) do
    Laravex.Env.load!(app.base_path)
    Laravex.Config.Repository.load!(app.base_path)

    if Process.whereis(Laravex.Container), do: Laravex.Container.instance(:app, app)

    middleware = Laravex.Http.Middleware.new()

    middleware =
      if app.middleware_callback do
        case app.middleware_callback.(middleware) do
          %Laravex.Http.Middleware{} = updated -> updated
          _ -> middleware
        end
      else
        middleware
      end

    warn_missing_app_key()

    exceptions = Laravex.Foundation.Exceptions.new()

    exceptions =
      if app.exceptions_callback do
        app.exceptions_callback.(exceptions)
      else
        exceptions
      end

    Laravex.Routing.Router.reset()
    Laravex.Console.Router.reset()

    unless Laravex.Routing.RouteCache.load!(app.base_path) do
      register_http_routes(app)
    end

    if app.console_routes && Code.ensure_loaded?(Routes.Console) do
      Routes.Console.register()
    end

    Enum.each(Bootstrap.Providers.list(), fn provider_mod ->
      if function_exported?(provider_mod, :register, 0), do: provider_mod.register()
    end)

    Enum.each(Bootstrap.Providers.list(), fn provider_mod ->
      if function_exported?(provider_mod, :boot, 0), do: provider_mod.boot()
    end)

    instance = %{
      base_path: app.base_path,
      middleware: middleware,
      exceptions: exceptions,
      health: app.health
    }

    :persistent_term.put({__MODULE__, :instance}, instance)
    %{app | instance: instance}
  end

  def instance do
    :persistent_term.get({__MODULE__, :instance}, nil)
  end

  def base_path do
    case instance() do
      %{base_path: path} -> path
      _ -> File.cwd!()
    end
  end

  def handle_request(%Laravex.Http.Request{} = request) do
    app = instance() || create(Bootstrap.App.build())

    try do
      Laravex.Http.Kernel.handle(request, app)
    rescue
      e in [Laravex.Validation.Failed] ->
        Laravex.Foundation.Exceptions.render(app.exceptions, request, e)

      e ->
        Laravex.Foundation.Exceptions.render(app.exceptions, request, e)
    end
  end

  def register_http_routes(%__MODULE__{} = app) do
    if app.health do
      Laravex.Routing.Router.get(app.health, fn _req ->
        Laravex.Http.Response.new(200, "OK", [{"content-type", "text/plain; charset=utf-8"}])
      end)
    end

    Laravex.Routing.Router.get("/health", fn _req ->
      Laravex.Foundation.Health.check()
    end)

    if app.web_routes && Code.ensure_loaded?(Routes.Web) do
      Routes.Web.register()
    end

    maybe_register(Module.concat(["Routes", "Api"]))
    maybe_register(Module.concat(["Routes", "Auth"]))
    :ok
  end

  defp maybe_register(mod) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :register, 0) do
      apply(mod, :register, [])
    end
  end

  defp warn_missing_app_key do
    key = Laravex.Config.Repository.get("app.key") || Laravex.Env.get("APP_KEY")

    if (is_nil(key) or key == "") and not testing?() and not Application.get_env(:laravex, :app_key_warned, false) do
      Application.put_env(:laravex, :app_key_warned, true)
      IO.puts(:stderr, "WARNING: APP_KEY is not set. Run `./artisan key:generate`.")
    end
  end

  defp testing? do
    (Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test) or
      Laravex.Env.get("APP_ENV") in ["testing", "test"]
  end
end
