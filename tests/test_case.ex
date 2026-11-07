defmodule Laravex.TestCase do
  @moduledoc """
  Port of tests/TestCase.php
  """

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
    Laravex.Foundation.Application.handle_request(request)
  end

  def assert_status(%Laravex.Http.Response{status: status}, expected) do
    assert status == expected
  end
end
