defmodule Laravex.Eloquex do
  @moduledoc """
  Eloquex — Laravex's Eloquent-shaped ORM.

  Prefer `use Laravex.Eloquex.Model, table: "…"`.
  `Laravex.Database.Model` remains as a compatibility alias.
  """

  def model, do: Laravex.Eloquex.Model
  def factory, do: Laravex.Eloquex.Factory
  def relation, do: Laravex.Eloquex.Relation
end
