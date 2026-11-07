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

    middleware = Laravex.Http.Middleware.new()

    middleware =
      if app.middleware_callback do
        app.middleware_callback.(middleware)
        middleware
      else
        middleware
      end

    exceptions = Laravex.Foundation.Exceptions.new()

    exceptions =
      if app.exceptions_callback do
        app.exceptions_callback.(exceptions)
      else
        exceptions
      end

    Laravex.Routing.Router.reset()
    Laravex.Console.Router.reset()

    if app.health do
      Laravex.Routing.Router.get(app.health, fn _req ->
        Laravex.Http.Response.new(200, "OK", [{"content-type", "text/plain; charset=utf-8"}])
      end)
    end

    if app.web_routes && Code.ensure_loaded?(Routes.Web) do
      Routes.Web.register()
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
      e ->
        Laravex.Foundation.Exceptions.render(app.exceptions, request, e)
    end
  end
end
