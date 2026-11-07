defmodule Tests.Feature.ExampleTest do
  use Laravex.TestCase, async: false

  test "the application returns a successful response" do
    response = get("/")
    assert_status(response, 200)
    assert_see(response, "Laravex")
  end

  test "the health endpoint is up" do
    response = get("/up")
    assert_status(response, 200)
  end
end
