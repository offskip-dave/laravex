defmodule Tests.Unit.Framework1343PortTest do
  use ExUnit.Case, async: true

  alias Laravex.Support.Str
  alias Laravex.Http.UrlSigner
  alias Laravex.Filesystem.Storage
  alias Laravex.Validation
  alias Laravex.Queue.Worker

  test "Str.is_blank?/is_not_blank?" do
    assert Str.is_blank?("")
    assert Str.is_blank?(nil)
    assert Str.is_blank?("   ")
    refute Str.is_blank?("ok")
    assert Str.is_not_blank?("ok")
    refute Str.is_not_blank?("")
  end

  test "not_regex fails on match and on invalid utf8-like apply failure" do
    assert {:ok, _} = Validation.validate(%{"x" => "hello"}, %{"x" => ["not_regex:foo"]})
    assert {:error, _} = Validation.validate(%{"x" => "foobar"}, %{"x" => ["not_regex:foo"]})
  end

  test "UrlSigner rejects non-scalar expires" do
    future = System.system_time(:second) + 3600
    path = UrlSigner.sign("/foo", expires: future)
    assert UrlSigner.valid?(path)

    # Array expires must never look valid (#62411)
    req = struct(Laravex.Http.Request, path: "/foo", query: %{"expires" => ["99999999999"], "signature" => "x"})
    refute UrlSigner.valid?(req)
  end

  test "merge_files_with_input lets blank input yield to files" do
    files = %{"avatar" => %{name: "a.png"}}
    merged = Validation.merge_files_with_input(%{"avatar" => ""}, files)
    assert merged["avatar"] == files["avatar"]

    merged2 = Validation.merge_files_with_input(%{"avatar" => "keep"}, files)
    assert merged2["avatar"] == "keep"
  end

  test "release_using_backoff picks delay for attempt" do
    assert Worker.release_using_backoff("10,30,60", 1) == 10
    assert Worker.release_using_backoff("10,30,60", 2) == 30
    assert Worker.release_using_backoff("10,30,60", 5) == 60
    assert Worker.release_using_backoff(15, 3) == 15
  end

  test "copy_to_disk / move_to_disk are exported" do
    {:module, _} = Code.ensure_loaded(Storage)
    funs = Storage.__info__(:functions)
    assert {:copy_to_disk, 4} in funs
    assert {:move_to_disk, 4} in funs
  end
end
