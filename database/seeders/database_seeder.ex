defmodule Database.Seeders.DatabaseSeeder do
  @moduledoc """
  Port of database/seeders/DatabaseSeeder.php
  """

  def run do
    # Mirror Laravel's commented default: User::factory()->create([...])
    user =
      Database.Factories.UserFactory.make(%{
        "name" => "Test User",
        "email" => "test@example.com"
      })

    {:ok, user}
  end
end
