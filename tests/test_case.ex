defmodule Laravex.TestCase do
  @moduledoc "Port of tests/TestCase.php with Laravel-like HTTP helpers."

  use ExUnit.CaseTemplate

  using do
    quote do
      import Laravex.TestCase
    end
  end

  setup do
    Laravex.Foundation.Server.boot!()
    :ok
  end

  def get(path, headers \\ %{}) do
    request = Laravex.Http.Request.capture("GET", path, headers)
    response = Laravex.Foundation.Application.handle_request(request)
    Laravex.Observability.record_request(request, response)
    response
  end

  def post(path, body \\ %{}, headers \\ %{}) do
    encoded =
      body
      |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end)
      |> Enum.join("&")

    headers = Map.put(headers, "content-type", "application/x-www-form-urlencoded")
    request = Laravex.Http.Request.capture("POST", path, headers, encoded)
    Laravex.Foundation.Application.handle_request(request)
  end

  def acting_as(user) do
    Process.put(:laravex_acting_as, user)
    user
  end

  def assert_status(%Laravex.Http.Response{status: status}, expected) do
    assert status == expected
  end

  def assert_see(%Laravex.Http.Response{body: body}, text) do
    assert String.contains?(body, text)
  end

  def assert_json(%Laravex.Http.Response{body: body}, expected) when is_map(expected) do
    {:ok, decoded} = Laravex.Support.JSON.decode(body)

    Enum.each(expected, fn {k, v} ->
      assert Map.get(decoded, to_string(k)) == v
    end)
  end

  def refresh_database do
    Laravex.Database.Migrator.refresh()
  end
end
