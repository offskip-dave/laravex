defmodule Tests.Unit.ConfigAndDatabaseTest do
  use Laravex.TestCase, async: false

  test "all default config files load" do
    Enum.each(Laravex.Config.Repository.files(), fn name ->
      assert Map.has_key?(Laravex.Config.Repository.all(), name), "missing config #{name}"
    end)

    assert Laravex.Config.Repository.get("auth.providers.users.model") == App.Models.User
    assert Laravex.Config.Repository.get("app.name") != nil
  end

  test "default migrations factory and seeder are invokable" do
    assert is_integer(Laravex.Database.Migrator.run_default_migrations())
    tables = Laravex.Database.Migrator.tables()

    assert "users" in tables
    assert "cache" in tables
    assert "jobs" in tables

    user = Database.Factories.UserFactory.make()
    assert user.email

    # Avoid unique email conflict on re-runs
    email = "test#{System.unique_integer([:positive])}@example.com"
    created = Database.Factories.UserFactory.create(%{"email" => email, "name" => "Test User"})
    assert created.id
    assert created.email == email
  end

  test "inspire console command is registered" do
    assert ExUnit.CaptureIO.capture_io(fn ->
             Laravex.Console.Router.dispatch("inspire")
           end) =~ "."
  end

  test "cache mail and storage services work" do
    assert :ok = Laravex.Cache.Manager.put("k", "v")
    assert "v" == Laravex.Cache.Manager.get("k")

    Laravex.Mail.Mailer.fake()
    assert :ok = Laravex.Mail.Mailer.send(%{to: "a@b.c", subject: "Hi", body: "x"})
    assert Laravex.Mail.Mailer.assert_sent(fn m -> m.subject == "Hi" end)

    assert :ok = Laravex.Filesystem.Storage.put("hello.txt", "world")
    assert Laravex.Filesystem.Storage.exists?("hello.txt")
    assert "world" == Laravex.Filesystem.Storage.get("hello.txt")
  end

  test "events validation and translation" do
    test_pid = self()
    Laravex.Events.Dispatcher.listen(:ping, fn data -> send(test_pid, {:pinged, data}) end)
    Laravex.Events.Dispatcher.dispatch(:ping, %{ok: true})
    assert_receive {:pinged, %{ok: true}}

    assert {:ok, _} = Laravex.Validation.validate(%{"email" => "a@b.c"}, %{"email" => "required|email"})
    assert {:error, _} = Laravex.Validation.validate(%{}, %{"email" => "required"})

    assert Laravex.Translation.get("messages.welcome") == "Welcome to Laravex"
  end
end
