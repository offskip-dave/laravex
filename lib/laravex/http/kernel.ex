defmodule Laravex.Http.Kernel do
  @moduledoc false

  def handle(%Laravex.Http.Request{} = request, app) do
    clear_request_process()

    case Laravex.Routing.Router.match(request) do
      :error ->
        not_found(request)

      {:ok, request, handler, opts} ->
        plugs = resolve_plugs(app.middleware, opts)

        case Laravex.Http.Middleware.run(request, plugs) do
          {:halt, %Laravex.Http.Response{} = response} ->
            response = terminate(plugs, request, response)
            maybe_record(request, response)
            response

          {:ok, request} ->
            request =
              Laravex.Session.Store.put(request, "_previous.url", request.path)

            Process.put(:laravex_request, request)

            response =
              case Laravex.Routing.Router.invoke(handler, request, opts) do
                %Laravex.Http.Response{} = response ->
                  persist_session(Process.get(:laravex_request, request), response)

                body when is_binary(body) ->
                  persist_session(
                    Process.get(:laravex_request, request),
                    Laravex.Http.Response.html(body)
                  )

                other ->
                  persist_session(
                    Process.get(:laravex_request, request),
                    Laravex.Http.Response.html(inspect(other))
                  )
              end

            response = terminate(plugs, Process.get(:laravex_request, request), response)
            maybe_record(request, response)
            response
        end
    end
  end

  defp maybe_record(request, response) do
    if truthy?(Laravex.Config.Repository.get("app.debug", false)) or
         Application.get_env(:laravex, :observability, false) do
      Laravex.Observability.record_request(request, response)
    end
  rescue
    _ -> :ok
  end

  def persist_session(%{session_id: sid, session: session}, response)
      when is_binary(sid) do
    Laravex.Session.Store.save(sid, session)
    name = Laravex.Config.Repository.get("session.cookie", "laravex-session")
    encrypt? = truthy?(Laravex.Config.Repository.get("session.encrypt", false))
    value = if encrypt?, do: Laravex.Encryption.Crypt.encrypt(sid), else: sid

    response =
      Laravex.Http.Response.with_cookie(response, name, value,
        path: Laravex.Config.Repository.get("session.path", "/"),
        http_only: truthy?(Laravex.Config.Repository.get("session.http_only", true))
      )

    attach_remember_cookie(response)
  end

  def persist_session(_request, response), do: attach_remember_cookie(response)

  defp attach_remember_cookie(response) do
    case Process.get(:laravex_remember_cookie) do
      {value, true} when is_binary(value) and value != "" ->
        Laravex.Http.Response.with_cookie(
          response,
          Laravex.Auth.Guard.remember_cookie_name(),
          value,
          max_age: 60 * 60 * 24 * 365,
          http_only: true
        )

      {_, false} ->
        Laravex.Http.Response.with_cookie(
          response,
          Laravex.Auth.Guard.remember_cookie_name(),
          "",
          max_age: 0,
          http_only: true
        )

      _ ->
        response
    end
  end

  defp terminate(plugs, request, response) do
    plugs
    |> Enum.reverse()
    |> Enum.reduce(response, fn plug, resp ->
      mod = plug_mod(plug)

      if function_exported?(mod, :terminate, 2) do
        case mod.terminate(request, resp) do
          %Laravex.Http.Response{} = next -> next
          {:ok, %Laravex.Http.Response{} = next} -> next
          _ -> resp
        end
      else
        resp
      end
    end)
  end

  defp plug_mod({mod, _opts}) when is_atom(mod), do: mod
  defp plug_mod(mod) when is_atom(mod), do: mod
  defp plug_mod(_), do: __MODULE__

  defp resolve_plugs(middleware, opts) do
    groups = Keyword.get(opts, :middleware, ["web"])

    group_plugs =
      groups
      |> List.wrap()
      |> Enum.flat_map(fn
        "web" -> Laravex.Http.Middleware.web_group(middleware)
        "api" -> Laravex.Http.Middleware.api_group(middleware)
        other when is_atom(other) -> [{other, []}]
        other when is_binary(other) -> [Laravex.Http.Middleware.resolve_alias(other)]
        {mod, plug_opts} when is_atom(mod) -> [{mod, plug_opts}]
        _ -> []
      end)

    Laravex.Http.Middleware.global(middleware) ++ group_plugs
  end

  defp not_found(request) do
    if Laravex.Http.Request.wants_json?(request) or Laravex.Http.Request.is?(request, "api/*") or
         Laravex.Http.Request.ajax?(request) do
      Laravex.Http.Response.json(%{message: "Not Found"}, 404)
    else
      Laravex.Http.Response.html(
        "<!DOCTYPE html><html><body><h1>404</h1><p>Not Found</p></body></html>",
        404
      )
    end
  end

  defp clear_request_process do
    Enum.each(
      [
        :laravex_request,
        :laravex_remember_cookie,
        :laravex_cors_request,
        :laravex_cache_headers,
        :laravex_queued_cookies,
        :laravex_flash_now,
        :laravex_peer,
        :laravex_client_ip,
        :laravex_client_secure,
        :laravex_client_host
      ],
      &Process.delete/1
    )
  end

  defp truthy?(v), do: v in [true, "true", 1, "1"]
end
