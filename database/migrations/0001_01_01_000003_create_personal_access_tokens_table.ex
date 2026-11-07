defmodule Database.Migrations.CreatePersonalAccessTokensTable do
  @moduledoc "Sanctum-like personal access tokens table."

  def up do
    [
      {:create, "personal_access_tokens",
       [
         {:id, :bigserial, primary: true},
         {:string, "tokenable_type"},
         {:big_integer, "tokenable_id", []},
         {:string, "name"},
         {:string, "token", unique: true},
         {:text, "abilities", nullable: true},
         {:timestamp, "last_used_at", nullable: true},
         {:timestamp, "expires_at", nullable: true},
         {:timestamps, true}
       ]}
    ]
    |> Laravex.Database.Migrator.apply()
  end

  def down do
    Laravex.Database.Migrator.drop(["personal_access_tokens"])
  end
end
