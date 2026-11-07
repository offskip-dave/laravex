defmodule Laravex.Http.Middleware.TrustProxies do
  @moduledoc """
  Honor `X-Forwarded-*` when the peer is a trusted proxy (Laravel TrustProxies).

  Configure via `TRUSTED_PROXIES` (`*` or comma-separated hosts) or
  `config("app.trusted_proxies")`.
  """

  def handle(request, _opts) do
    if trusted?(request) do
      ip = first_forwarded(Laravex.Http.Request.header(request, "x-forwarded-for"))
      proto = Laravex.Http.Request.header(request, "x-forwarded-proto")
      host = Laravex.Http.Request.header(request, "x-forwarded-host")

      if ip, do: Process.put(:laravex_client_ip, ip)
      if proto, do: Process.put(:laravex_client_secure, String.downcase(to_string(proto)) == "https")
      if host, do: Process.put(:laravex_client_host, host)
    end

    {:ok, request}
  end

  defp trusted?(_request) do
    case trusted_proxies() do
      :all -> true
      [] -> false
      _list -> true
    end
  end

  defp trusted_proxies do
    raw =
      Laravex.Config.Repository.get("app.trusted_proxies") ||
        Laravex.Env.get("TRUSTED_PROXIES", nil)

    cond do
      is_nil(raw) or raw == "" or raw == false -> []
      raw in ["*", true, "true"] -> :all
      is_binary(raw) -> String.split(raw, ",", trim: true)
      is_list(raw) -> raw
      true -> []
    end
  end

  defp first_forwarded(nil), do: nil

  defp first_forwarded(value) when is_binary(value) do
    value
    |> String.split(",", parts: 2)
    |> hd()
    |> String.trim()
    |> case do
      "" -> nil
      ip -> ip
    end
  end
end

defmodule Laravex.Http.Middleware.HandleCors do
  @moduledoc "CORS headers + OPTIONS preflight (Laravel HandleCors)."

  def handle(request, _opts) do
    if matches_path?(request.path) do
      if request.method == "OPTIONS" do
        {:halt, cors_response(request, Laravex.Http.Response.new(204, ""))}
      else
        Process.put(:laravex_cors_request, request)
        {:ok, request}
      end
    else
      {:ok, request}
    end
  end

  def terminate(_request, %Laravex.Http.Response{} = response) do
    case Process.get(:laravex_cors_request) do
      %Laravex.Http.Request{} = req -> cors_response(req, response)
      _ -> response
    end
  end

  defp matches_path?(path) do
    paths = Laravex.Config.Repository.get("cors.paths", ["api/*"])

    Enum.any?(List.wrap(paths), fn pattern ->
      Laravex.Http.Request.is?(%Laravex.Http.Request{path: path}, pattern)
    end)
  end

  defp cors_response(request, response) do
    origin = Laravex.Http.Request.header(request, "origin") || "*"
    allowed_origins = List.wrap(Laravex.Config.Repository.get("cors.allowed_origins", ["*"]))
    allow_origin = resolve_origin(origin, allowed_origins)

    methods =
      case Laravex.Config.Repository.get("cors.allowed_methods", ["*"]) do
        ["*"] -> "GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS"
        list -> Enum.join(List.wrap(list), ", ")
      end

    headers =
      case Laravex.Config.Repository.get("cors.allowed_headers", ["*"]) do
        ["*"] ->
          Laravex.Http.Request.header(request, "access-control-request-headers") || "*"

        list ->
          Enum.join(List.wrap(list), ", ")
      end

    exposed =
      Laravex.Config.Repository.get("cors.exposed_headers", [])
      |> List.wrap()
      |> Enum.join(", ")

    max_age = Laravex.Config.Repository.get("cors.max_age", 0)
    credentials? = truthy?(Laravex.Config.Repository.get("cors.supports_credentials", false))

    cors_headers =
      [
        {"access-control-allow-origin", allow_origin},
        {"access-control-allow-methods", methods},
        {"access-control-allow-headers", headers}
      ]
      |> then(fn h ->
        if exposed != "", do: [{"access-control-expose-headers", exposed} | h], else: h
      end)
      |> then(fn h ->
        if max_age && max_age != 0,
          do: [{"access-control-max-age", to_string(max_age)} | h],
          else: h
      end)
      |> then(fn h ->
        if credentials?, do: [{"access-control-allow-credentials", "true"} | h], else: h
      end)

    %{response | headers: cors_headers ++ response.headers}
  end

  defp resolve_origin(_origin, ["*"]), do: "*"
  defp resolve_origin(origin, allowed) when is_binary(origin) do
    if origin in allowed, do: origin, else: List.first(allowed) || "*"
  end

  defp resolve_origin(_, _), do: "*"

  defp truthy?(v), do: v in [true, "true", 1, "1"]
end

defmodule Laravex.Http.Middleware.TrimStrings do
  @moduledoc "Trim string request input (except password fields)."

  @except ~w(password password_confirmation current_password)

  def handle(request, opts) do
    except = Keyword.get(opts, :except, @except) |> Enum.map(&to_string/1)
    params = map_strings(request.params, except, &String.trim/1)
    {:ok, %{request | params: params}}
  end

  defp map_strings(map, except, fun) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = to_string(k)

      cond do
        key in except ->
          {k, v}

        is_binary(v) ->
          {k, fun.(v)}

        is_map(v) ->
          {k, map_strings(v, except, fun)}

        is_list(v) ->
          {k, Enum.map(v, fn item -> if is_map(item), do: map_strings(item, except, fun), else: item end)}

        true ->
          {k, v}
      end
    end)
  end
end

defmodule Laravex.Http.Middleware.ConvertEmptyStringsToNull do
  @moduledoc "Convert empty string request input to nil."

  def handle(request, _opts) do
    {:ok, %{request | params: nullify(request.params)}}
  end

  defp nullify(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      cond do
        v == "" -> {k, nil}
        is_map(v) -> {k, nullify(v)}
        is_list(v) -> {k, Enum.map(v, &nullify_value/1)}
        true -> {k, v}
      end
    end)
  end

  defp nullify_value(""), do: nil
  defp nullify_value(v) when is_map(v), do: nullify(v)
  defp nullify_value(v), do: v
end
