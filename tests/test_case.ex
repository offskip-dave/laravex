defmodule Laravex.TestCase do
  @moduledoc "Port of tests/TestCase.php — feature HTTP helpers + assertions."

  use ExUnit.CaseTemplate

  using do
    quote do
      import Laravex.TestCase
      import ExUnit.Assertions
    end
  end

  setup do
    Process.delete(:laravex_acting_as)
    Process.delete(:laravex_request)
    _ = Laravex.Foundation.Server.boot!()
    :ok
  end

  # --- actingAs -------------------------------------------------------------

  def acting_as(user) do
    Process.put(:laravex_acting_as, user)
    user
  end

  def without_acting_as do
    Process.delete(:laravex_acting_as)
    :ok
  end

  # --- HTTP verbs -----------------------------------------------------------

  def get(path, headers \\ %{}), do: call("GET", path, %{}, headers)

  def post(path, body \\ %{}, headers \\ %{}) do
    call("POST", path, body, headers)
  end

  def put(path, body \\ %{}, headers \\ %{}) do
    call("PUT", path, body, headers)
  end

  def patch(path, body \\ %{}, headers \\ %{}) do
    call("PATCH", path, body, headers)
  end

  def delete(path, body \\ %{}, headers \\ %{}) do
    call("DELETE", path, body, headers)
  end

  def json(method, path, body \\ %{}, headers \\ %{}) do
    headers =
      headers
      |> Map.new(fn {k, v} -> {to_string(k), to_string(v)} end)
      |> Map.put_new("accept", "application/json")
      |> Map.put_new("content-type", "application/json")

    call(String.upcase(to_string(method)), path, body, headers)
  end

  defp call(method, path, body, headers) do
    headers = Map.new(headers || %{}, fn {k, v} -> {to_string(k), to_string(v)} end)
    {raw_body, headers} = encode_body(body, headers)

    request = Laravex.Http.Request.capture(method, path, headers, raw_body)
    Laravex.Foundation.Application.handle_request(request)
  end

  defp encode_body(body, headers) when is_map(body) or is_list(body) do
    ct = Map.get(headers, "content-type", "")

    cond do
      String.contains?(ct, "application/json") or headers["accept"] == "application/json" ->
        {Laravex.Support.JSON.encode!(body), Map.put_new(headers, "content-type", "application/json")}

      true ->
        {URI.encode_query(Map.new(body, fn {k, v} -> {to_string(k), to_string(v)} end)),
         Map.put_new(headers, "content-type", "application/x-www-form-urlencoded")}
    end
  end

  defp encode_body(body, headers) when is_binary(body), do: {body, headers}
  defp encode_body(_, headers), do: {"", headers}

  # --- assertions -----------------------------------------------------------

  def assert_status(%Laravex.Http.Response{status: status}, expected) do
    assert status == expected
  end

  def assert_ok(%Laravex.Http.Response{} = resp), do: assert_status(resp, 200)
  def assert_created(%Laravex.Http.Response{} = resp), do: assert_status(resp, 201)
  def assert_no_content(%Laravex.Http.Response{} = resp), do: assert_status(resp, 204)

  def assert_see(%Laravex.Http.Response{body: body}, text) do
    assert String.contains?(body, text)
  end

  def assert_dont_see(%Laravex.Http.Response{body: body}, text) do
    refute String.contains?(body, text)
  end

  def assert_redirected(%Laravex.Http.Response{} = resp, to \\ nil) do
    assert resp.status in [301, 302, 303, 307, 308]

    location =
      Enum.find_value(resp.headers, fn
        {"location", v} -> v
        {"Location", v} -> v
        _ -> nil
      end)

    assert is_binary(location)

    if to do
      assert location == to or String.ends_with?(location, to)
    end

    resp
  end

  def assert_json(%Laravex.Http.Response{body: body}, expected \\ nil) do
    decoded =
      case Laravex.Support.JSON.decode(body) do
        {:ok, data} -> data
        _ -> flunk("Response body is not valid JSON: #{inspect(body)}")
      end

    if expected do
      assert_json_subset(decoded, expected)
    end

    decoded
  end

  defp assert_json_subset(actual, expected) when is_map(expected) and is_map(actual) do
    Enum.each(expected, fn {k, v} ->
      key = to_string(k)
      assert Map.has_key?(actual, key) or Map.has_key?(actual, k),
             "Missing JSON key #{inspect(key)}"

      actual_v = Map.get(actual, key) || Map.get(actual, k)
      assert_json_subset(actual_v, v)
    end)
  end

  defp assert_json_subset(actual, expected), do: assert actual == expected

  def session(key, default \\ nil) do
    case Process.get(:laravex_request) do
      %{session: session} when is_map(session) -> Map.get(session, to_string(key), default)
      _ -> default
    end
  end

  def assert_session_has(key, value \\ :__present__) do
    actual = session(key, :__missing__)
    assert actual != :__missing__, "Session missing key #{inspect(key)}"

    if value != :__present__ do
      assert actual == value
    end
  end
end
