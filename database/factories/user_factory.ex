defmodule Database.Factories.UserFactory do
  @moduledoc "Port of database/factories/UserFactory.php"

  def definition do
    %{
      "name" => fake_name(),
      "email" => fake_email(),
      "email_verified_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "password" => "password",
      "remember_token" => Laravex.Support.Helpers.str_random(10)
    }
  end

  def make(attrs \\ %{}) do
    definition()
    |> Map.merge(stringify_keys(attrs))
    |> then(&App.Models.User.new/1)
  end

  def create(attrs \\ %{}) do
    definition()
    |> Map.merge(stringify_keys(attrs))
    |> then(&App.Models.User.create/1)
  end

  def unverified(attrs \\ %{}) do
    make(Map.put(stringify_keys(attrs), "email_verified_at", nil))
  end

  defp fake_name do
    Enum.random(["Ada Lovelace", "Grace Hopper", "Alan Turing", "Katherine Johnson"])
  end

  defp fake_email do
    "user#{System.unique_integer([:positive])}@example.com"
  end

  defp stringify_keys(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
