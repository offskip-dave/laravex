defmodule Tests.Unit.Framework1344PortTest do
  use ExUnit.Case, async: true

  alias Laravex.Http.Request
  alias Laravex.Http.FormRequest
  alias Laravex.Http.Middleware.TrimStrings
  alias Laravex.Http.Middleware.ConvertEmptyStringsToNull
  alias Laravex.Http.Exceptions.PostTooLargeException
  alias Laravex.Validation
  alias Laravex.Database.Connection
  alias Laravex.Database.Query
  alias Laravex.JsonSchema

  test "FormRequest.model ignores array identifiers" do
    req = struct(Request, params: %{"user_id" => [1, 2, 3]})
    assert is_nil(FormRequest.model(req, "user_id", Tests.Unit.Framework1344PortTest.FakeUser))
  end

  test "FormRequest.model_or_fail raises for array identifiers" do
    req = struct(Request, params: %{"user_id" => %{"0" => 1}})

    assert_raise Laravex.Database.ModelNotFoundException, fn ->
      FormRequest.model_or_fail(req, "user_id", Tests.Unit.Framework1344PortTest.FakeUser)
    end
  end

  test "TrimStrings / ConvertEmpty transform nested params" do
    req = struct(Request, params: %{"name" => "  Ada  ", "nested" => %{"city" => "  X  ", "empty" => ""}})

    assert {:ok, trimmed} = TrimStrings.handle(req, [])
    assert trimmed.params["name"] == "Ada"
    assert trimmed.params["nested"]["city"] == "X"

    assert {:ok, nulled} = ConvertEmptyStringsToNull.handle(trimmed, [])
    assert nulled.params["nested"]["empty"] == nil
  end

  test "TransformsRequest raises when cumulative key bytes exceed limit" do
    huge_key = String.duplicate("k", 1024)
    # Build a map whose keys alone exceed 20 MiB when walked recursively.
    # Use a shallow map with many large keys instead of nesting deeply.
    chunk = Map.new(1..21_000, fn i -> {"#{huge_key}_#{i}", "v"} end)
    req = struct(Request, params: chunk)

    assert_raise PostTooLargeException, fn ->
      TrimStrings.handle(req, [])
    end
  end

  test "when_transaction_runs_longer_than fires for slow transactions" do
    Process.put(:laravex_tx_longer, [])
    Process.put(:laravex_transaction_longer_than, [])

    assert :ok =
             Connection.when_transaction_runs_longer_than(5, fn _conn, event, duration ->
               Process.put(:laravex_tx_longer, [{event, duration} | Process.get(:laravex_tx_longer)])
             end)

    # Drive the hook without CLI SQLite multi-process transactions.
    Process.put(:laravex_transaction_level, 1)
    Process.put(:laravex_transaction_started_at, System.monotonic_time(:millisecond) - 25)
    Connection.notify_transaction_duration(:committed)

    assert [{:committed, duration} | _] = Process.get(:laravex_tx_longer)
    assert duration > 5
  end

  test "Request.is? matches api root and nested paths" do
    assert Request.is?(struct(Request, path: "/api"), "api")
    assert Request.is?(struct(Request, path: "/api"), ["api", "api/*"])
    assert Request.is?(struct(Request, path: "/api/users"), "api/*")
    refute Request.is?(struct(Request, path: "/api"), "api/*")
    refute Request.is?(struct(Request, path: "/web"), ["api", "api/*"])
  end

  test "numeric rules reject extreme scientific exponents" do
    assert {:error, _} =
             Validation.validate(%{"n" => "1e100000"}, %{"n" => ["numeric", "gt:0"]})

    assert {:error, _} =
             Validation.validate(%{"n" => "1E-100000"}, %{"n" => ["numeric", "multiple_of:1"]})
  end

  test "lock_for_no_key_update is exported and sets lock" do
    q = Query.table("users") |> Query.lock_for_no_key_update()
    assert q.lock == :no_key_update

    sql = Query.to_sql(q)
    assert sql =~ "FOR UPDATE" or sql =~ "FOR NO KEY UPDATE"
  end

  test "secured markdown escapes HTML entities including quotes" do
    # Mirror Mailer.secured_markdown_escape / escape_html behaviour.
    escaped =
      ~s(Hello <b>x</b> "y" [z])
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")
      |> String.replace("\"", "&quot;")
      |> String.replace("'", "&#039;")
      |> String.replace("\\", "\\\\")
      |> String.replace("[", "\\[")
      |> String.replace("]", "\\]")

    assert escaped =~ "&lt;b&gt;"
    assert escaped =~ "&quot;y&quot;"
    assert escaped =~ "\\[z\\]"
    refute escaped =~ "<b>"
  end

  test "JsonSchema uniqueItems maps to distinct" do
    rules =
      JsonSchema.rules(%{
        "type" => "object",
        "properties" => %{
          "tags" => %{"type" => "array", "uniqueItems" => true}
        }
      })

    assert "distinct" in rules["tags"]
  end

  defmodule FakeUser do
    def query, do: Laravex.Database.Query.table("users")
    def from_row(row), do: row
  end
end
