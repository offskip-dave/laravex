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
    assert :ok = Laravex.Database.Migrator.run_default_migrations()
    tables = Laravex.Database.Migrator.tables()

    assert "users" in tables
    assert "cache" in tables
    assert "jobs" in tables

    user = Database.Factories.UserFactory.make()
    assert user.email
    assert {:ok, seeded} = Database.Seeders.DatabaseSeeder.run()
    assert seeded.email == "test@example.com"
  end

  test "inspire console command is registered" do
    assert :ok =
             ExUnit.CaptureIO.capture_io(fn ->
               Laravex.Console.Router.dispatch("inspire")
             end)
             |> then(fn _ -> :ok end)
  end
end
