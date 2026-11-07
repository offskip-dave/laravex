defmodule Laravex.Http.Kernel do
  @moduledoc false

  def handle(%Laravex.Http.Request{} = request, app) do
    case Laravex.Http.Middleware.run_web(request, app.middleware) do
      {:halt, %Laravex.Http.Response{} = response} ->
        response

      {:ok, request} ->
        case Laravex.Routing.Router.dispatch(request) do
          {:ok, %Laravex.Http.Response{} = response} ->
            maybe_persist_session(request, response)

          {:ok, body} when is_binary(body) ->
            maybe_persist_session(request, Laravex.Http.Response.html(body))

          :error ->
            Laravex.Http.Response.html(
              "<!DOCTYPE html><html><body><h1>404</h1><p>Not Found</p></body></html>",
              404
            )
        end
    end
  end

  defp maybe_persist_session(%{session_id: sid, session: session}, response)
       when is_binary(sid) do
    Laravex.Session.Store.save(sid, session)
    name = Laravex.Config.Repository.get("session.cookie", "laravex-session")
    Laravex.Http.Response.with_cookie(response, name, sid)
  end

  defp maybe_persist_session(_request, response), do: response
end
