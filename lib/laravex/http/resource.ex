defmodule Laravex.Http.Resource do
  @moduledoc """
  Laravel-style JSON API resource.

      defmodule App.Http.Resources.UserResource do
        use Laravex.Http.Resource

        def to_map(user) do
          merge(%{
            id: user.id,
            name: user.name,
            posts: when_loaded(user, :posts)
          })
        end
      end
  """

  @missing :__laravex_missing__

  defmacro __using__(_opts) do
    quote do
      import Laravex.Http.Resource, only: [when_loaded: 2, when_loaded: 3, merge: 1]

      def collection(models) when is_list(models), do: Enum.map(models, &to_map/1)

      def make(model) do
        Laravex.Http.Response.json(%{data: to_map(model)})
      end

      def collection_response(models) when is_list(models) do
        Laravex.Http.Response.json(%{data: collection(models)})
      end

      def paginated(page) when is_map(page) do
        Laravex.Http.Response.json_paginated(page, &to_map/1)
      end
    end
  end

  @doc """
  Include a value only when the relation was eager-loaded (`with` / `load`).
  Unloaded relations become a MissingValue stripped by `merge/1`.
  """
  def when_loaded(model, relation) do
    when_loaded(model, relation, & &1)
  end

  def when_loaded(model, relation, fun) when is_function(fun, 1) do
    if Laravex.Database.Model.relation_loaded?(model, relation) do
      fun.(Laravex.Database.Model.get_relation(model, relation))
    else
      @missing
    end
  end

  @doc "Drop MissingValue entries from a resource map (Laravel `mergeWhen` lite)."
  def merge(attrs) when is_map(attrs) do
    attrs
    |> Enum.reject(fn {_k, v} -> v == @missing end)
    |> Map.new()
  end

  def missing_value, do: @missing
end
