defmodule App.Models.User do
  @moduledoc """
  Port of app/Models/User.php
  """

  defstruct [
    :id,
    :name,
    :email,
    :email_verified_at,
    :password,
    :remember_token,
    :created_at,
    :updated_at
  ]

  def fillable, do: ["name", "email", "password"]
  def hidden, do: ["password", "remember_token"]

  def casts do
    %{
      "email_verified_at" => :datetime,
      "password" => :hashed
    }
  end

  def new(attrs \\ %{}) when is_map(attrs) do
    allowed =
      attrs
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Enum.filter(fn {k, _} -> k in fillable() or k in ["id", "email_verified_at", "remember_token", "created_at", "updated_at"] end)
      |> Map.new(fn {k, v} -> {String.to_atom(k), cast(k, v)} end)

    struct(__MODULE__, allowed)
  end

  def factory, do: Database.Factories.UserFactory

  defp cast("email_verified_at", nil), do: nil
  defp cast("email_verified_at", value), do: value
  defp cast("password", "hashed:" <> _ = value), do: value
  defp cast("password", value) when is_binary(value), do: hash_password(value)
  defp cast(_key, value), do: value

  defp hash_password(password) do
    salt = :crypto.strong_rand_bytes(16)
    hash = :crypto.hash(:sha256, salt <> password)
    "hashed:" <> Base.encode16(salt <> hash, case: :lower)
  end
end
