defmodule Laravex.Http.Request do
  @moduledoc false

  defstruct method: "GET",
            path: "/",
            query: %{},
            headers: %{},
            body: "",
            expects_json: false

  def capture(method, path, headers \\ %{}, body \\ "") do
    {path, query} = split_path(path)
    headers = normalize_headers(headers)

    %__MODULE__{
      method: String.upcase(to_string(method)),
      path: path,
      query: query,
      headers: headers,
      body: body,
      expects_json: headers_expect_json?(headers)
    }
  end

  def is?(%__MODULE__{path: path}, pattern) when is_binary(pattern) do
    pattern =
      pattern
      |> String.replace("*", ".*")
      |> then(&("^" <> &1 <> "$"))

    Regex.match?(Regex.compile!(pattern), path)
  end

  def expects_json?(%__MODULE__{expects_json: true}), do: true
  def expects_json?(%__MODULE__{}), do: false

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
    query
    |> URI.query_decoder()
    |> Enum.into(%{})
  end

  defp normalize_headers(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
    |> Map.new()
  end
end
