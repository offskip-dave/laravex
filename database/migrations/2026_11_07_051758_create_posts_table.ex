defmodule Database.Migrations.CreatePostsTable do
  def up do
    Laravex.Database.Schema.create("table_name", fn t ->
      t
      |> Laravex.Database.Blueprint.id()
      |> Laravex.Database.Blueprint.timestamps()
    end)
  end

  def down do
    Laravex.Database.Schema.drop_if_exists("table_name")
  end
end
