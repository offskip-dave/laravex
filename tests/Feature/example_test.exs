defmodule Tests.Feature.ExampleTest do
  @moduledoc """
  Port of tests/Feature/ExampleTest.php
  """

  use Laravex.TestCase, async: false

  test "the application returns a successful response" do
    response = get("/")
    assert_status(response, 200)
  end

  test "the health endpoint is up" do
    response = get("/up")
    assert_status(response, 200)
  end
end
