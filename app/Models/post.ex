defmodule App.Models.Post do
  defstruct [:id, :created_at, :updated_at]
  use Laravex.Database.Model, table: "posts"
  def fillable, do: []
  def casts, do: %{}
end
