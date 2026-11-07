defmodule Database.Seeders.DatabaseSeeder do
  @moduledoc "Port of database/seeders/DatabaseSeeder.php"

  def run do
    user =
      Database.Factories.UserFactory.create(%{
        "name" => "Test User",
        "email" => "test@example.com"
      })

    {:ok, user}
  end
end
