defmodule Laravex.Http.Client do
  @moduledoc """
  Lightweight outbound HTTP client (Laravel Http facade lite) via OTP `:httpc`.

      Laravex.Http.Client.get("https://example.com")

      Laravex.Http.Client.accept_json()
      |> Laravex.Http.Client.send(:post, "https://example.com", body: %{ok: true})

  Testing:

      Laravex.Http.Client.fake()
      Laravex.Http.Client.stub("https://api.test/*", %{status: 200, body: %{"ok" => true}})
      Laravex.Http.Client.get("https://api.test/users")
      Laravex.Http.Client.assert_sent(fn req -> req.method == :get end)
  """

  @fake_key :laravex_http_fake
  @sent_key :laravex_http_sent
  @stubs_key :laravex_http_stubs

  defstruct headers: [], options: []

  def new(opts \\ []), do: %__MODULE__{headers: [], options: opts}

  def with_headers(%__MODULE__{} = client, headers) when is_map(headers) or is_list(headers) do
    %{client | headers: merge_headers(client.headers, headers)}
  end

  def with_headers(headers) when is_map(headers) or is_list(headers) do
    with_headers(new(), headers)
  end

  def accept_json(%__MODULE__{} = client) do
    with_headers(client, %{"Accept" => "application/json", "Content-Type" => "application/json"})
  end

  def accept_json, do: accept_json(new())

  def with_token(%__MODULE__{} = client, token, type \\ "Bearer") do
    with_headers(client, %{"Authorization" => "#{type} #{token}"})
  end

  def get(url, opts \\ []) when is_binary(url), do: request(:get, url, opts)
  def head(url, opts \\ []) when is_binary(url), do: request(:head, url, opts)
  def delete(url, opts \\ []) when is_binary(url), do: request(:delete, url, opts)

  def post(url, body \\ "", opts \\ []) when is_binary(url) do
    request(:post, url, Keyword.put(opts, :body, body))
  end

  def put(url, body \\ "", opts \\ []) when is_binary(url) do
    request(:put, url, Keyword.put(opts, :body, body))
  end

  def patch(url, body \\ "", opts \\ []) when is_binary(url) do
    request(:patch, url, Keyword.put(opts, :body, body))
  end

  @doc "Dispatch a request using a pending client (headers/options)."
  def send(%__MODULE__{} = client, method, url, opts \\ [])
      when is_atom(method) and is_binary(url) do
    request(method, url, merge_client_opts(client, opts))
  end

  def request(method, url, opts \\ []) when is_atom(method) and is_binary(url) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    headers = normalize_headers(Keyword.get(opts, :headers, []))
    query = Keyword.get(opts, :query, %{})
    url = append_query(url, query)
    body_in = Keyword.get(opts, :body, "")
    body = encode_body(body_in, headers)

    record_sent(%{
      method: method,
      url: url,
      headers: headers_to_map(headers),
      body: body_in
    })

    response =
      if fake?() do
        fake_response(url)
      else
        real_request(method, url, headers, body, timeout)
      end

    maybe_throw(response, opts)
  end

  def json(%{body: body} = response) when is_binary(body) do
    case Laravex.Support.JSON.decode(body) do
      {:ok, decoded} -> %{response | body: decoded}
      _ -> response
    end
  end

  def json(response), do: response

  def successful?(%{status: status}) when is_integer(status), do: status >= 200 and status < 300
  def redirect?(%{status: status}) when is_integer(status), do: status >= 300 and status < 400
  def client_error?(%{status: status}) when is_integer(status), do: status >= 400 and status < 500
  def server_error?(%{status: status}) when is_integer(status), do: status >= 500

  def fake do
    Process.put(@fake_key, true)
    Process.put(@sent_key, [])
    Process.put(@stubs_key, [])
    :ok
  end

  def stub(url_pattern, response) when is_binary(url_pattern) do
    stubs = Process.get(@stubs_key, [])
    Process.put(@stubs_key, stubs ++ [{url_pattern, normalize_stub(response)}])
    :ok
  end

  def sent, do: Enum.reverse(Process.get(@sent_key, []))

  def assert_sent(fun) when is_function(fun, 1) do
    Enum.any?(sent(), fun)
  end

  defp fake?, do: Process.get(@fake_key, false) == true

  defp record_sent(entry) do
    if fake?(), do: Process.put(@sent_key, [entry | Process.get(@sent_key, [])])
    :ok
  end

  defp fake_response(url) do
    stub =
      Process.get(@stubs_key, [])
      |> Enum.find(fn {pattern, _} -> url_match?(pattern, url) end)

    case stub do
      {_, resp} -> resp
      nil -> %{status: 200, headers: %{}, body: ""}
    end
  end

  defp normalize_stub(%{status: _} = resp) do
    body = Map.get(resp, :body, "")
    body = if is_map(body) or is_list(body), do: Laravex.Support.JSON.encode!(body), else: body

    %{
      status: Map.get(resp, :status, 200),
      headers: Map.get(resp, :headers, %{}),
      body: body
    }
  end

  defp normalize_stub(body) when is_map(body) or is_list(body) do
    %{
      status: 200,
      headers: %{"content-type" => "application/json"},
      body: Laravex.Support.JSON.encode!(body)
    }
  end

  defp normalize_stub(body) when is_binary(body), do: %{status: 200, headers: %{}, body: body}
  defp normalize_stub(other), do: %{status: 200, headers: %{}, body: to_string(other)}

  defp url_match?(pattern, url) do
    if String.contains?(pattern, "*") do
      regex =
        pattern
        |> Regex.escape()
        |> String.replace("\\*", ".*")

      Regex.match?(Regex.compile!("^" <> regex <> "$"), url)
    else
      pattern == url or String.starts_with?(url, pattern)
    end
  end

  defp real_request(method, url, headers, body, timeout) do
    ensure_apps!()
    url_chars = String.to_charlist(url)
    headers_c = Enum.map(headers, fn {k, v} -> {to_c(k), to_c(v)} end)

    request =
      case method do
        m when m in [:get, :head, :delete, :options, :trace] ->
          {url_chars, headers_c}

        _ ->
          content_type =
            Enum.find_value(headers_c, fn {k, v} ->
              if String.downcase(List.to_string(k)) == "content-type", do: v
            end) || ~c"application/json"

          body_bin = IO.iodata_to_binary(body)
          {url_chars, headers_c, content_type, body_bin}
      end

    http_opts = [{:timeout, timeout}, {:connect_timeout, timeout}]
    opts_httpc = [{:body_format, :binary}]

    case :httpc.request(method, request, http_opts, opts_httpc) do
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

  defp maybe_throw(response, opts) do
    if Keyword.get(opts, :throw, false) and not successful?(response) do
      raise RuntimeError, "HTTP request returned #{response.status}"
    else
      response
    end
  end

  defp merge_client_opts(%__MODULE__{headers: headers, options: base}, opts) do
    opts = if Keyword.keyword?(opts), do: opts, else: []

    Keyword.merge(base, opts)
    |> Keyword.update(:headers, headers, fn h -> merge_headers(headers, h) end)
  end

  defp merge_headers(left, right) do
    (headers_to_list(left) ++ headers_to_list(right))
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      Map.put(acc, String.downcase(to_string(k)), {to_string(k), v})
    end)
    |> Map.values()
  end

  defp headers_to_list(headers) when is_list(headers), do: headers
  defp headers_to_list(headers) when is_map(headers), do: Map.to_list(headers)

  defp headers_to_map(headers) do
    Map.new(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
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
    if content_type?(headers, "application/x-www-form-urlencoded") do
      URI.encode_query(Map.new(body, fn {k, v} -> {to_string(k), to_string(v)} end))
    else
      Laravex.Support.JSON.encode!(body)
    end
  end

  defp encode_body(other, _), do: to_string(other)

  defp content_type?(headers, type) do
    Enum.any?(headers, fn {k, v} ->
      String.downcase(to_string(k)) == "content-type" and String.contains?(to_string(v), type)
    end)
  end

  defp normalize_headers(headers) do
    Enum.map(headers_to_list(headers), fn
      {k, v} -> {to_c(k), to_c(v)}
      other -> other
    end)
  end

  defp to_c(v) when is_list(v), do: v
  defp to_c(v), do: v |> to_string() |> String.to_charlist()
end
