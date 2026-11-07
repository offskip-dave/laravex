defmodule Laravex.Http.Kernel do
  @moduledoc false

  def handle(%Laravex.Http.Request{} = request, app) do
    case Laravex.Routing.Router.match(request) do
      :error ->
        not_found()

      {:ok, request, handler, opts} ->
        plugs = resolve_plugs(app.middleware, opts)

        case Laravex.Http.Middleware.run(request, plugs) do
          {:halt, %Laravex.Http.Response{} = response} ->
            response

          {:ok, request} ->
            case Laravex.Routing.Router.invoke(handler, request, opts) do
              %Laravex.Http.Response{} = response ->
                persist_session(request, response)

              body when is_binary(body) ->
                persist_session(request, Laravex.Http.Response.html(body))

              other ->
                persist_session(request, Laravex.Http.Response.html(inspect(other)))
            end
        end
    end
  end

  def persist_session(%{session_id: sid, session: session}, response) when is_binary(sid) do
    Laravex.Session.Store.save(sid, session)
    name = Laravex.Config.Repository.get("session.cookie", "laravex-session")
    Laravex.Http.Response.with_cookie(response, name, sid)
  end

  def persist_session(_request, response), do: response

  defp resolve_plugs(middleware, opts) do
    groups = Keyword.get(opts, :middleware, ["web"])

    groups
    |> List.wrap()
    |> Enum.flat_map(fn
      "web" -> Laravex.Http.Middleware.web_group(middleware)
      "api" -> Laravex.Http.Middleware.api_group(middleware)
      other when is_atom(other) -> [other]
      other when is_binary(other) -> [Module.concat([other])]
      _ -> []
    end)
  end

  defp not_found do
    Laravex.Http.Response.html(
      "<!DOCTYPE html><html><body><h1>404</h1><p>Not Found</p></body></html>",
      404
    )
  end
end
