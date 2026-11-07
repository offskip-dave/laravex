defmodule Database.Migrations.CreateUsersTable do
  @moduledoc """
  Port of 0001_01_01_000000_create_users_table.php
  """

  def up do
    [
      {:create, "users",
       [
         {:id, :bigserial, primary: true},
         {:string, "name"},
         {:string, "email", unique: true},
         {:timestamp, "email_verified_at", nullable: true},
         {:string, "password"},
         {:remember_token, true},
         {:timestamps, true}
       ]},
      {:create, "password_reset_tokens",
       [
         {:string, "email", primary: true},
         {:string, "token"},
         {:timestamp, "created_at", nullable: true}
       ]},
      {:create, "sessions",
       [
         {:string, "id", primary: true},
         {:foreign_id, "user_id", nullable: true, index: true},
         {:string, "ip_address", length: 45, nullable: true},
         {:text, "user_agent", nullable: true},
         {:long_text, "payload"},
         {:integer, "last_activity", index: true}
       ]}
    ]
    |> Laravex.Database.Migrator.apply()
  end

  def down do
    Laravex.Database.Migrator.drop(["users", "password_reset_tokens", "sessions"])
  end
end
