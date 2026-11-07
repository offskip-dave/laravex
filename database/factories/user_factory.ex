defmodule Database.Factories.UserFactory do
  @moduledoc "Port of database/factories/UserFactory.php (Eloquex factory)."

  use Laravex.Eloquex.Factory, model: App.Models.User

  def definition do
    %{
      "name" => fake_name(),
      "email" => fake_email(),
      "email_verified_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "password" => "password",
      "remember_token" => Laravex.Support.Helpers.str_random(10)
    }
  end

  defstate :unverified do
    %{"email_verified_at" => nil}
  end

  def unverified(attrs \\ %{}), do: make_state(:unverified, attrs)

  defp fake_name do
    Enum.random(["Ada Lovelace", "Grace Hopper", "Alan Turing", "Katherine Johnson"])
  end

  defp fake_email do
    "user#{System.unique_integer([:positive])}@example.com"
  end
end
