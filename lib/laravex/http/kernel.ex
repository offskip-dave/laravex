defmodule Laravex.Http.Kernel do
  @moduledoc false

  def handle(%Laravex.Http.Request{} = request, app) do
    {:ok, request} = Laravex.Http.Middleware.run_web(request, app.middleware)

    case Laravex.Routing.Router.dispatch(request) do
      {:ok, %Laravex.Http.Response{} = response} ->
        response

      {:ok, body} when is_binary(body) ->
        Laravex.Http.Response.html(body)

      :error ->
        Laravex.Http.Response.new(404, "Not Found", [
          {"content-type", "text/plain; charset=utf-8"}
        ])
    end
  end
end
