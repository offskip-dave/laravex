defmodule Bootstrap.App do
  @moduledoc """
  Port of bootstrap/app.php
  """

  alias Laravex.Foundation.Application
  alias Laravex.Foundation.Exceptions
  alias Laravex.Http.Request

  def build(base_path \\ File.cwd!()) do
    Application.configure(base_path: base_path)
    |> Application.with_routing(
      web: Path.join(base_path, "routes/web.ex"),
      commands: Path.join(base_path, "routes/console.ex"),
      health: "/up"
    )
    |> Application.with_middleware(fn middleware ->
      middleware
    end)
    |> Application.with_exceptions(fn exceptions ->
      Exceptions.should_render_json_when(exceptions, fn request ->
        Request.is?(request, "api/*") or Request.expects_json?(request)
      end)
    end)
  end
end
