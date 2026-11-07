defmodule Laravex.Http.Client do
  @moduledoc """
  Lightweight outbound HTTP client (Laravel Http facade lite) via OTP `:httpc`.

      Laravex.Http.Client.get("https://example.com")
      Laravex.Http.Client.post(url, Jason-compatible body, headers: [{"content-type", "application/json"}])
  """

  def get(url, opts \\ []), do: request(:get, url, opts)
  def head(url, opts \\ []), do: request(:head, url, opts)
  def delete(url, opts \\ []), do: request(:delete, url, opts)

  def post(url, body \\ "", opts \\ []) do
    request(:post, url, Keyword.put(opts, :body, body))
  end

  def put(url, body \\ "", opts \\ []) do
    request(:put, url, Keyword.put(opts, :body, body))
  end

  def patch(url, body \\ "", opts \\ []) do
    request(:patch, url, Keyword.put(opts, :body, body))
  end

  def request(method, url, opts \\ []) when is_atom(method) and is_binary(url) do
    ensure_apps!()
    timeout = Keyword.get(opts, :timeout, 30_000)
    headers = normalize_headers(Keyword.get(opts, :headers, []))
    query = Keyword.get(opts, :query, %{})
    url = append_query(url, query)
    body = encode_body(Keyword.get(opts, :body, ""), headers)

    http_method = method |> Atom.to_string() |> String.upcase() |> String.to_charlist()
    url_chars = String.to_charlist(url)

    request =
      case method do
        m when m in [:get, :head, :delete] ->
          {url_chars, headers}

        _ ->
          content_type =
            headers
            |> Enum.find_value(fn {k, v} ->
              if String.downcase(to_string(k)) == "content-type", do: to_c(v)
            end) || ~c"application/octet-stream"

          {url_chars, headers, content_type, body}
      end

    http_opts = [{:timeout, timeout}, {:connect_timeout, timeout}]
    opts_httpc = [{:body_format, :binary}]

    case :httpc.request(http_method, request, http_opts, opts_httpc) do
      {:ok, {{_http, status, _reason}, resp_headers, resp_body}} ->
        %{
          status: status,
          headers: Map.new(resp_headers, fn {k, v} -> {to_string(k), to_string(v)} end),
          body: resp_body
        }

      {:ok, {status, resp_body}} when is_integer(status) ->
        %{status: status, headers: %{}, body: resp_body}

      {:error, reason} ->
        raise RuntimeError, "HTTP request failed: #{inspect(reason)}"
    end
  end

  def json(%{body: body} = response) do
    case Laravex.Support.JSON.decode(body) do
      {:ok, decoded} -> %{response | body: decoded}
      _ -> response
    end
  end

  defp ensure_apps! do
    {:ok, _} = Application.ensure_all_started(:inets)
    _ = Application.ensure_all_started(:ssl)
    :ok
  end

  defp append_query(url, query) when query == %{}, do: url

  defp append_query(url, query) when is_map(query) do
    q = URI.encode_query(Map.new(query, fn {k, v} -> {to_string(k), to_string(v)} end))
    if String.contains?(url, "?"), do: url <> "&" <> q, else: url <> "?" <> q
  end

  defp encode_body(body, _headers) when is_binary(body), do: body
  defp encode_body(body, _headers) when is_list(body), do: IO.iodata_to_binary(body)

  defp encode_body(body, headers) when is_map(body) do
    if content_type?(headers, "application/json") do
      Laravex.Support.JSON.encode!(body)
    else
      URI.encode_query(Map.new(body, fn {k, v} -> {to_string(k), to_string(v)} end))
    end
  end

  defp encode_body(other, _), do: to_string(other)

  defp content_type?(headers, type) do
    Enum.any?(headers, fn {k, v} ->
      String.downcase(to_string(k)) == "content-type" and String.contains?(to_string(v), type)
    end) or headers == []
  end

  defp normalize_headers(headers) do
    Enum.map(headers, fn
      {k, v} -> {to_c(k), to_c(v)}
      other -> other
    end)
  end

  defp to_c(v) when is_list(v), do: v
  defp to_c(v), do: v |> to_string() |> String.to_charlist()
end
