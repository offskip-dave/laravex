defmodule Laravex.Http.Middleware.TrustHosts do
  @moduledoc """
  Reject requests whose Host header is not trusted (Laravel TrustHosts).

  Configure `TRUSTED_HOSTS` (comma-separated) or `config("app.trusted_hosts")`.
  Empty/nil allows all hosts. Patterns may use a leading `*.` subdomain wildcard.
  """

  def handle(request, _opts) do
    case trusted_hosts() do
      [] ->
        {:ok, request}

      hosts ->
        host = request_host(request)

        if host && Enum.any?(hosts, &match_host?(&1, host)) do
          {:ok, request}
        else
          {:halt, Laravex.Http.Response.html("Invalid Host header.", 400)}
        end
    end
  end

  defp trusted_hosts do
    raw =
      Laravex.Config.Repository.get("app.trusted_hosts") ||
        Laravex.Env.get("TRUSTED_HOSTS", nil)

    cond do
      is_nil(raw) or raw == "" or raw == false ->
        []

      is_binary(raw) ->
        String.split(raw, ",", trim: true)

      is_list(raw) ->
        Enum.map(raw, &to_string/1)

      true ->
        []
    end
  end

  defp request_host(request) do
    Process.get(:laravex_client_host) ||
      Laravex.Http.Request.header(request, "x-forwarded-host") ||
      Laravex.Http.Request.header(request, "host")
  end

  defp match_host?(pattern, host) do
    pattern = String.downcase(String.trim(pattern))
    host = String.downcase(String.trim(host)) |> strip_port()

    cond do
      pattern == host ->
        true

      String.starts_with?(pattern, "*.") ->
        suffix = String.trim_leading(pattern, "*.")
        host == suffix or String.ends_with?(host, "." <> suffix)

      true ->
        false
    end
  end

  defp strip_port(host) do
    case String.split(host, ":", parts: 2) do
      [h, _] -> h
      [h] -> h
    end
  end
end

defmodule Laravex.Http.Middleware.SetCacheHeaders do
  @moduledoc """
  Set Cache-Control / ETag on the response (`cache.headers` alias).

      Router.get("/asset", handler, middleware: ["cache.headers:public;max_age=60;etag"])
  """

  def handle(request, opts) do
    Process.put(:laravex_cache_headers, opts)
    {:ok, request}
  end

  def terminate(_request, %Laravex.Http.Response{} = response) do
    case Process.get(:laravex_cache_headers) do
      nil ->
        response

      opts when is_list(opts) ->
        apply_headers(response, opts)

      _ ->
        response
    end
  end

  def parse_arg(nil), do: []
  def parse_arg(""), do: []

  def parse_arg(arg) when is_binary(arg) do
    arg
    |> String.split(";", trim: true)
    |> Enum.reduce([], fn part, acc ->
      part = String.trim(part)

      cond do
        part in ["public", "private", "no_cache", "no_store", "must_revalidate", "etag"] ->
          Keyword.put(acc, String.to_atom(part), true)

        String.contains?(part, "=") ->
          [k, v] = String.split(part, "=", parts: 2)
          key = k |> String.trim() |> String.to_atom()
          val = String.trim(v)

          value =
            case Integer.parse(val) do
              {n, ""} -> n
              _ -> val
            end

          Keyword.put(acc, key, value)

        true ->
          acc
      end
    end)
  end

  defp apply_headers(response, opts) do
    directives =
      []
      |> maybe_dir(opts, :public, "public")
      |> maybe_dir(opts, :private, "private")
      |> maybe_dir(opts, :no_cache, "no-cache")
      |> maybe_dir(opts, :no_store, "no-store")
      |> maybe_dir(opts, :must_revalidate, "must-revalidate")
      |> then(fn d ->
        case Keyword.get(opts, :max_age) do
          n when is_integer(n) -> ["max-age=#{n}" | d]
          _ -> d
        end
      end)
      |> Enum.reverse()

    headers =
      if directives != [] do
        [{"cache-control", Enum.join(directives, ", ")} | response.headers]
      else
        response.headers
      end

    headers =
      if Keyword.get(opts, :etag) do
        etag = :crypto.hash(:sha256, response.body) |> Base.encode16(case: :lower)
        [{"etag", ~s("#{etag}")} | headers]
      else
        headers
      end

    %{response | headers: headers}
  end

  defp maybe_dir(dirs, opts, key, value) do
    if Keyword.get(opts, key), do: [value | dirs], else: dirs
  end
end

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

  defp trusted?(request) do
    case trusted_proxies() do
      :all ->
        true

      [] ->
        false

      list ->
        peer = request.peer || Process.get(:laravex_peer)
        is_binary(peer) and Enum.any?(list, &match_proxy?(&1, peer))
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
      is_list(raw) -> Enum.map(raw, &to_string/1)
      true -> []
    end
  end

  defp match_proxy?(pattern, peer) do
    pattern = String.trim(to_string(pattern))
    peer = String.trim(to_string(peer))

    cond do
      pattern == peer -> true
      String.contains?(pattern, "/") -> in_cidr?(peer, pattern)
      true -> false
    end
  end

  defp in_cidr?(ip, cidr) do
    case String.split(cidr, "/") do
      [base, bits] ->
        with {:ok, ip_t} <- :inet.parse_address(String.to_charlist(ip)),
             {:ok, base_t} <- :inet.parse_address(String.to_charlist(base)),
             {bits_i, ""} <- Integer.parse(bits),
             true <- tuple_size(ip_t) == 4 and tuple_size(base_t) == 4 do
          mask = ipv4_mask(bits_i)
          Bitwise.band(ipv4_int(ip_t), mask) == Bitwise.band(ipv4_int(base_t), mask)
        else
          _ -> false
        end

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp ipv4_int({a, b, c, d}), do: a * 16_777_216 + b * 65_536 + c * 256 + d

  defp ipv4_mask(0), do: 0

  defp ipv4_mask(bits) when bits in 1..32 do
    Bitwise.bsl(0xFFFFFFFF, 32 - bits) |> Bitwise.band(0xFFFFFFFF)
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
