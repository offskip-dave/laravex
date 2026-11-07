defmodule Database.Migrations.CreateNotificationsTable do
  @moduledoc "Laravel-style notifications inbox table."

  def up do
    [
      {:create, "notifications",
       [
         {:string, "id", primary: true},
         {:string, "type"},
         {:string, "notifiable_type"},
         {:big_integer, "notifiable_id", []},
         {:text, "data", []},
         {:timestamp, "read_at", nullable: true},
         {:timestamps, true}
       ]}
    ]
    |> Laravex.Database.Migrator.apply()
  end

  def down do
    Laravex.Database.Migrator.drop(["notifications"])
  end
end
