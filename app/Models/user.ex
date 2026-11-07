defmodule App.Models.User do
  @moduledoc "Port of app/Models/User.php with Eloquent-shaped persistence."

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

  use Laravex.Database.Model, table: "users"
  use Laravex.Notifications.Notifiable

  def fillable, do: ["name", "email", "password"]
  def hidden, do: ["password", "remember_token"]

  def casts do
    %{
      "email_verified_at" => :datetime,
      "password" => :hashed
    }
  end

  def factory, do: Database.Factories.UserFactory
end
