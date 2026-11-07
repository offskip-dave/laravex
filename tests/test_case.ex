defmodule Laravex.TestCase do
  @moduledoc "Port of tests/TestCase.php"

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
    request = Laravex.Http.Request.capture("GET", path, Map.new(headers, fn {k, v} -> {to_string(k), to_string(v)} end))
    Laravex.Foundation.Application.handle_request(request)
  end

  def assert_status(%Laravex.Http.Response{status: status}, expected) do
    assert status == expected
  end

  def assert_see(%Laravex.Http.Response{body: body}, text) do
    assert String.contains?(body, text)
  end
end
