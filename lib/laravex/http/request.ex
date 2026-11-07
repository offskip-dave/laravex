defmodule Laravex.Http.Request do
  @moduledoc false

  defstruct method: "GET",
            path: "/",
            query: %{},
            headers: %{},
            body: "",
            params: %{},
            files: %{},
            cookies: %{},
            session: %{},
            session_id: nil,
            user: nil,
            expects_json: false,
            route_params: %{},
            errors: %{},
            old: %{},
            flash: %{},
            peer: nil,
            validated: %{}

  def capture(method, path, headers \\ %{}, body \\ "", opts \\ []) do
    {path, query} = split_path(path)
    headers = normalize_headers(headers)
    cookies = parse_cookies(Map.get(headers, "cookie", ""))
    {params, files} = parse_body(headers, body)
    peer = Keyword.get(opts, :peer)

    %__MODULE__{
      method: String.upcase(to_string(method)),
      path: path,
      query: query,
      headers: headers,
      body: body,
      params: Map.merge(query, params),
      files: files,
      cookies: cookies,
      expects_json: headers_expect_json?(headers),
      peer: peer
    }
  end

  def input(%__MODULE__{params: params}, key, default \\ nil) do
    Map.get(params, key) || Map.get(params, to_string(key), default)
  end

  def file(%__MODULE__{files: files}, key) do
    Map.get(files, to_string(key)) || Map.get(files, key)
  end

  def all(%__MODULE__{params: params}), do: params

  def only(%__MODULE__{params: params}, keys) when is_list(keys) do
    keys = Enum.map(keys, &to_string/1)

    params
    |> Enum.filter(fn {k, _} -> to_string(k) in keys end)
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  def except(%__MODULE__{params: params}, keys) when is_list(keys) do
    keys = Enum.map(keys, &to_string/1)

    params
    |> Enum.reject(fn {k, _} -> to_string(k) in keys end)
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  def has?(%__MODULE__{} = request, key) do
    k = to_string(key)
    Map.has_key?(request.params, k) or Map.has_key?(request.params, key)
  end

  def missing?(%__MODULE__{} = request, key), do: not has?(request, key)

  def filled?(%__MODULE__{} = request, key) do
    case input(request, key) do
      nil -> false
      "" -> false
      [] -> false
      %{} = m -> map_size(m) > 0
      _ -> true
    end
  end

  def boolean(%__MODULE__{} = request, key) do
    case input(request, key) do
      v when v in [true, 1, "1", "true", "on", "yes"] -> true
      _ -> false
    end
  end

  def integer(%__MODULE__{} = request, key, default \\ 0) do
    case input(request, key) do
      v when is_integer(v) -> v
      v when is_float(v) -> trunc(v)
      v when is_binary(v) ->
        case Integer.parse(String.trim(v)) do
          {n, _} -> n
          :error -> default
        end
      _ -> default
    end
  end

  def float(%__MODULE__{} = request, key, default \\ 0.0) do
    case input(request, key) do
      v when is_float(v) -> v
      v when is_integer(v) -> v * 1.0
      v when is_binary(v) ->
        case Float.parse(String.trim(v)) do
          {n, _} -> n
          :error -> default
        end
      _ -> default
    end
  end

  def date(%__MODULE__{} = request, key, default \\ nil) do
    case input(request, key) do
      %Date{} = d -> d
      %DateTime{} = dt -> DateTime.to_date(dt)
      %NaiveDateTime{} = ndt -> NaiveDateTime.to_date(ndt)
      v when is_binary(v) ->
        case Date.from_iso8601(String.slice(String.trim(v), 0, 10)) do
          {:ok, d} -> d
          _ -> default
        end
      _ -> default
    end
  end

  @doc "Call `fun` with the request when the key is present (Laravel `whenHas`)."
  def when_has(%__MODULE__{} = request, key, fun) when is_function(fun, 1) do
    if has?(request, key), do: fun.(request), else: request
  end

  @doc "Call `fun` with the request when the key is filled (Laravel `whenFilled`)."
  def when_filled(%__MODULE__{} = request, key, fun) when is_function(fun, 1) do
    if filled?(request, key), do: fun.(request), else: request
  end

  @doc "Merge input into the request (Laravel `Request::merge`)."
  def merge(%__MODULE__{params: params} = request, values) when is_map(values) do
    %{request | params: Map.merge(params, stringify_keys(values))}
  end

  @doc "Replace all request input (Laravel `Request::replace`)."
  def replace(%__MODULE__{} = request, values) when is_map(values) do
    %{request | params: stringify_keys(values)}
  end

  @doc "Merge only keys that are missing (Laravel `Request::mergeIfMissing`)."
  def merge_if_missing(%__MODULE__{params: params} = request, values) when is_map(values) do
    incoming =
      values
      |> stringify_keys()
      |> Enum.reject(fn {k, _} -> Map.has_key?(params, k) end)
      |> Map.new()

    %{request | params: Map.merge(params, incoming)}
  end

  def header(%__MODULE__{headers: headers}, key, default \\ nil) do
    Map.get(headers, String.downcase(to_string(key)), default)
  end

  def bearer_token(%__MODULE__{} = req) do
    case header(req, "authorization") do
      "Bearer " <> token -> token
      _ -> nil
    end
  end

  def is?(%__MODULE__{path: path}, pattern) when is_binary(pattern) do
    regex =
      pattern
      |> String.replace("*", ".*")
      |> then(&Regex.compile!("^" <> &1 <> "$"))

    Regex.match?(regex, path)
  end

  def expects_json?(%__MODULE__{expects_json: true}), do: true
  def expects_json?(%__MODULE__{} = request), do: wants_json?(request)

  @doc "Laravel `Request::wantsJson()` — Accept prefers JSON."
  def wants_json?(%__MODULE__{} = request) do
    accept = header(request, "accept") || ""

    String.contains?(accept, "application/json") or
      String.contains?(accept, "+json") or
      request.expects_json == true
  end

  @doc "Laravel `Request::ajax()` — X-Requested-With: XMLHttpRequest."
  def ajax?(%__MODULE__{} = request) do
    header(request, "x-requested-with") == "XMLHttpRequest"
  end

  @doc "Whether Accept includes any of the given content types."
  def accepts?(%__MODULE__{} = request, types) do
    accept = String.downcase(header(request, "accept") || "")

    Enum.any?(List.wrap(types), fn type ->
      String.contains?(accept, String.downcase(to_string(type)))
    end)
  end

  @doc "Absolute URL for the current request path + query."
  def full_url(%__MODULE__{} = request) do
    base = String.trim_trailing(to_string(Laravex.Config.Repository.get("app.url", "")), "/")
    query =
      if map_size(request.query || %{}) > 0 do
        "?" <> URI.encode_query(Map.new(request.query, fn {k, v} -> {to_string(k), to_string(v)} end))
      else
        ""
      end

    base <> request.path <> query
  end

  def safe?(%__MODULE__{method: method}), do: method in ["GET", "HEAD", "OPTIONS"]

  @doc "Client IP after TrustProxies (falls back to X-Real-IP / 127.0.0.1)."
  def ip(%__MODULE__{} = request) do
    Process.get(:laravex_client_ip) || header(request, "x-real-ip") || "127.0.0.1"
  end

  @doc "Whether the request is HTTPS after TrustProxies."
  def secure?(%__MODULE__{} = _request) do
    case Process.get(:laravex_client_secure) do
      true -> true
      _ -> false
    end
  end

  def validate(%__MODULE__{} = request, rules) do
    Laravex.Validation.validate(request.params, rules)
  end

  defp headers_expect_json?(headers) do
    accept = Map.get(headers, "accept", "")
    content_type = Map.get(headers, "content-type", "")

    String.contains?(accept, "application/json") or
      String.contains?(content_type, "application/json") or
      Map.get(headers, "x-requested-with") == "XMLHttpRequest"
  end

  defp split_path(path) do
    case String.split(path, "?", parts: 2) do
      [p] -> {normalize_path(p), %{}}
      [p, q] -> {normalize_path(p), parse_query(q)}
    end
  end

  defp normalize_path(""), do: "/"
  defp normalize_path(path), do: path

  defp parse_query(query) do
    query |> URI.query_decoder() |> Enum.into(%{}, fn {k, v} -> {k, v} end)
  end

  defp parse_body(headers, body) do
    ct = Map.get(headers, "content-type", "")

    cond do
      String.contains?(ct, "multipart/form-data") ->
        parse_multipart(ct, body)

      String.contains?(ct, "application/json") ->
        case Laravex.Support.JSON.decode(body) do
          {:ok, map} when is_map(map) -> {stringify_keys(map), %{}}
          _ -> {%{}, %{}}
        end

      String.contains?(ct, "application/x-www-form-urlencoded") ->
        {parse_query(body), %{}}

      true ->
        if body != "" and String.contains?(body, "="),
          do: {parse_query(body), %{}},
          else: {%{}, %{}}
    end
  end

  defp parse_multipart(content_type, body) do
    case Regex.run(~r/boundary=(?:"([^"]+)"|([^\s;]+))/i, content_type) do
      [_, b1, b2] ->
        boundary = if b1 != "", do: b1, else: b2
        parts = String.split(body, "--" <> boundary)

        Enum.reduce(parts, {%{}, %{}}, fn part, {params, files} ->
          part = String.trim(part)
          if part in ["", "--", "-"] do
            {params, files}
          else
            case String.split(part, "\r\n\r\n", parts: 2) do
              [raw_headers, raw_body] ->
                headers = parse_part_headers(raw_headers)
                value = String.trim_trailing(raw_body, "\r\n")
                name = Map.get(headers, "name")

                cond do
                  is_nil(name) ->
                    {params, files}

                  Map.has_key?(headers, "filename") ->
                    file =
                      Laravex.Http.UploadedFile.new(%{
                        filename: headers["filename"],
                        content_type: headers["content-type"] || "application/octet-stream",
                        contents: value
                      })

                    {params, Map.put(files, name, file)}

                  true ->
                    {Map.put(params, name, value), files}
                end

              _ ->
                {params, files}
            end
          end
        end)

      _ ->
        {%{}, %{}}
    end
  end

  defp parse_part_headers(raw) do
    raw
    |> String.split("\r\n")
    |> Enum.reduce(%{}, fn line, acc ->
      cond do
        String.match?(line, ~r/^content-disposition:/i) ->
          name =
            case Regex.run(~r/name="([^"]*)"/, line) do
              [_, n] -> n
              _ -> nil
            end

          filename =
            case Regex.run(~r/filename="([^"]*)"/, line) do
              [_, f] -> f
              _ -> nil
            end

          acc
          |> then(fn a -> if name, do: Map.put(a, "name", name), else: a end)
          |> then(fn a -> if filename, do: Map.put(a, "filename", filename), else: a end)

        String.match?(line, ~r/^content-type:/i) ->
          ct = line |> String.split(":", parts: 2) |> List.last() |> String.trim()
          Map.put(acc, "content-type", ct)

        true ->
          acc
      end
    end)
  end

  defp parse_cookies(""), do: %{}

  defp parse_cookies(header) do
    header
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reduce(%{}, fn part, acc ->
      case String.split(part, "=", parts: 2) do
        [k, v] -> Map.put(acc, k, URI.decode(v))
        _ -> acc
      end
    end)
  end

  defp normalize_headers(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
    |> Map.new()
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
