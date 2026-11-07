defmodule Database.Factories.UserFactory do
  @moduledoc """
  Port of database/factories/UserFactory.php
  """

  @password_holder :laravex_user_factory_password

  def definition do
    %{
      "name" => fake_name(),
      "email" => fake_email(),
      "email_verified_at" => DateTime.utc_now(),
      "password" => password(),
      "remember_token" => random_token(10)
    }
  end

  def make(attrs \\ %{}) do
    definition()
    |> Map.merge(stringify_keys(attrs))
    |> then(&App.Models.User.new/1)
  end

  def unverified(attrs \\ %{}) do
    make(Map.put(stringify_keys(attrs), "email_verified_at", nil))
  end

  defp password do
    case :persistent_term.get(@password_holder, :unset) do
      :unset ->
        hashed = App.Models.User.new(%{"password" => "password"}).password
        :persistent_term.put(@password_holder, hashed)
        hashed

      value ->
        value
    end
  end


  defp fake_name do
    Enum.random(["Ada Lovelace", "Grace Hopper", "Alan Turing", "Katherine Johnson"])
  end

  defp fake_email do
    "user#{System.unique_integer([:positive])}@example.com"
  end

  defp random_token(n) do
    :crypto.strong_rand_bytes(n) |> Base.url_encode64(padding: false) |> binary_part(0, n)
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
