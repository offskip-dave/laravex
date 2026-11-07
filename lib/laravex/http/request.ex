defmodule Laravex.Http.Request do
  @moduledoc false

  defstruct method: "GET",
            path: "/",
            query: %{},
            headers: %{},
            body: "",
            params: %{},
            cookies: %{},
            session: %{},
            session_id: nil,
            user: nil,
            expects_json: false,
            route_params: %{},
            errors: %{},
            old: %{}

  def capture(method, path, headers \\ %{}, body \\ "") do
    {path, query} = split_path(path)
    headers = normalize_headers(headers)
    cookies = parse_cookies(Map.get(headers, "cookie", ""))

    %__MODULE__{
      method: String.upcase(to_string(method)),
      path: path,
      query: query,
      headers: headers,
      body: body,
      params: Map.merge(query, parse_body(headers, body)),
      cookies: cookies,
      expects_json: headers_expect_json?(headers)
    }
  end

  def input(%__MODULE__{params: params}, key, default \\ nil) do
    Map.get(params, key) || Map.get(params, to_string(key), default)
  end

  def all(%__MODULE__{params: params}), do: params

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
  def expects_json?(%__MODULE__{}), do: false

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
      String.contains?(ct, "application/json") ->
        case Laravex.Support.JSON.decode(body) do
          {:ok, map} when is_map(map) -> stringify_keys(map)
          _ -> %{}
        end

      String.contains?(ct, "application/x-www-form-urlencoded") ->
        parse_query(body)

      true ->
        if body != "" and String.contains?(body, "="), do: parse_query(body), else: %{}
    end
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
