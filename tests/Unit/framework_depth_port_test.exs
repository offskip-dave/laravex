defmodule Tests.Unit.FrameworkDepthPortTest do
  use ExUnit.Case, async: true

  alias Laravex.Support.Str
  alias Laravex.Validation
  alias Laravex.Validation.Rule
  alias Laravex.View.AttributeBag
  alias Laravex.View.RawTemplate
  alias Laravex.JsonSchema
  alias Laravex.Http.Middleware
  alias Laravex.Database.Connection
  alias Laravex.Database.Model
  alias Laravex.Queue
  alias Laravex.Console.Schedule

  test "email rejects oversize, newlines, and bare @" do
    assert Str.is_email?("a@b.c")
    refute Str.is_email?("a@")
    refute Str.is_email?("a\n@b.com")
    long = String.duplicate("a", 250) <> "@b.co"
    refute Str.is_email?(long)
    assert {:error, _} = Validation.validate(%{"email" => "not-an-email"}, %{"email" => "email"})
  end

  test "AttributeBag escapes defaults and to_html" do
    bag =
      AttributeBag.new(%{"class" => "btn"})
      |> AttributeBag.merge(%{"title" => "x\"onclick=alert(1)"})

    html = AttributeBag.to_html(bag)
    assert html =~ "title=\"x&quot;onclick=alert(1)\""
    refute html =~ "title=\"x\"onclick"
  end

  test "mass-assignment normalizes hyphenated guarded keys" do
    assert Model.normalize_attribute_key("is-admin") == "is_admin"
    assert Model.normalize_attribute_key("isAdmin") == "is_admin"

    defmodule GuardedSample do
      def fillable, do: ["name"]
      def guarded, do: ["is_admin"]
    end

    refute Model.fillable?(GuardedSample, "is-admin")
    refute Model.fillable?(GuardedSample, "isAdmin")
    assert Model.fillable?(GuardedSample, "name")
    assert Model.guarded?(GuardedSample, "is-admin")
  end

  test "Rule.unique/exists accumulate where clauses" do
    rule =
      Rule.unique("users", "email")
      |> Rule.where("active", 1)
      |> Rule.where("tenant_id", 9)

    assert length(rule.wheres) == 2
    assert rule.type == :unique

    exists = Rule.exists("users") |> Rule.where_not_null("email")
    assert hd(exists.wheres) == {:not_null, "email"}
  end

  test "middleware replace/insert_before/insert_after" do
    m = Middleware.new()

    m =
      m
      |> Middleware.replace(Laravex.Http.Middleware.TrimStrings, [
        Laravex.Http.Middleware.TrimStrings,
        :custom_a
      ])
      |> Middleware.insert_before("web", Laravex.Http.Middleware.VerifyCsrfToken, :before_csrf)
      |> Middleware.insert_after("web", Laravex.Http.Middleware.VerifyCsrfToken, :after_csrf)

    global = Middleware.global(m)
    assert :custom_a in global

    web = Middleware.web_group(m)
    csrf_idx = Enum.find_index(web, &(&1 == Laravex.Http.Middleware.VerifyCsrfToken))
    assert Enum.at(web, csrf_idx - 1) == :before_csrf
    assert Enum.at(web, csrf_idx + 1) == :after_csrf
  end

  test "without_affecting_stickiness restores modification flag" do
    Connection.forget_record_modification_state()
    refute Connection.has_modified_records?()

    Connection.without_affecting_stickiness(fn ->
      Connection.records_have_been_modified(true)
      assert Connection.has_modified_records?()
    end)

    refute Connection.has_modified_records?()
  end

  test "RawTemplate renders inline blade" do
    html =
      RawTemplate.render(
        RawTemplate.new("<p>{{ message }}</p>"),
        %{"message" => "hi"}
      )

    assert html =~ "<p>hi</p>"
  end

  test "JsonSchema.rules derives validation map" do
    rules =
      JsonSchema.rules(%{
        "type" => "object",
        "required" => ["email"],
        "properties" => %{
          "email" => %{"type" => "string", "format" => "email", "maxLength" => 254},
          "age" => %{"type" => "integer", "minimum" => 0}
        }
      })

    assert "required" in rules["email"]
    assert "email" in rules["email"]
    assert "max:254" in rules["email"]
    assert "integer" in rules["age"]
  end

  test "Queue.when_job_runs_longer_than fires for slow jobs" do
    Process.put(:laravex_queue_longer_than, [])
    called = :ets.new(:longer_flag, [:set, :public])

    Queue.when_job_runs_longer_than(1, fn _job, duration ->
      :ets.insert(called, {:hit, duration})
    end)

    Queue.notify_job_duration(SomeJob, 50)
    assert [{:hit, 50}] = :ets.lookup(called, :hit)
  end

  test "Schedule.when_task_runs_longer_than registers hook" do
    Schedule.reset()
    assert :ok = Schedule.when_task_runs_longer_than(0.0001, fn _opts, _runtime -> :ok end)
  end
end
