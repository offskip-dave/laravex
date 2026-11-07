defmodule Laravex.Http.Resource do
  @moduledoc """
  Laravel-style JSON API resource.

      defmodule App.Http.Resources.UserResource do
        use Laravex.Http.Resource

        def to_map(user) do
          merge(%{
            id: user.id,
            name: user.name,
            posts: when_loaded(user, :posts),
            role: when_cond(user.admin?, "admin")
          })
          |> Map.merge(merge_when(user.admin?, %{role: "admin"}))
        end

        def additional(_user), do: %{meta: %{version: 1}}
      end

  Collections (Laravel `UserResource::collection($users)`):

      UserResource.collection(users) |> Laravex.Http.ResourceCollection.response()
      UserResource.collection_response(users)
  """

  @missing :__laravex_missing__

  defmacro __using__(_opts) do
    quote do
      import Laravex.Http.Resource,
        only: [
          when_loaded: 2,
          when_loaded: 3,
          when_cond: 2,
          when_cond: 3,
          merge: 1,
          merge_when: 2
        ]

      def wrap, do: "data"
      def additional(_resource), do: %{}

      @doc "Anonymous ResourceCollection for a list or paginator (Laravel `::collection`)."
      def collection(resources) do
        Laravex.Http.ResourceCollection.anonymous(__MODULE__, resources)
      end

      def make(model) do
        Laravex.Http.Resource.respond(__MODULE__, to_map(model), additional(model))
      end

      @doc "JSON response for a list or paginator via ResourceCollection."
      def collection_response(resources) do
        __MODULE__.collection(resources) |> Laravex.Http.ResourceCollection.response()
      end

      def paginated(page) when is_map(page) do
        collection_response(page)
      end

      defoverridable wrap: 0, additional: 1
    end
  end

  def respond(mod, data, extra \\ %{}) when is_map(extra) do
    payload =
      case mod.wrap() do
        false -> if is_map(data), do: data, else: %{"data" => data}
        nil -> if is_map(data), do: data, else: %{"data" => data}
        key -> %{to_string(key) => data}
      end

    Laravex.Http.Response.json(Map.merge(payload, stringify_keys(extra)))
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

  @doc "Laravel `$this->when` — value or MissingValue."
  def when_cond(condition, value) do
    if truthy?(condition), do: value, else: @missing
  end

  def when_cond(condition, value, default) do
    if truthy?(condition), do: value, else: default
  end

  @doc "Drop MissingValue entries from a resource map."
  def merge(attrs) when is_map(attrs) do
    attrs
    |> Enum.reject(fn {_k, v} -> v == @missing end)
    |> Map.new()
  end

  @doc "Laravel `mergeWhen` — merge attrs when condition is truthy."
  def merge_when(condition, attrs) when is_map(attrs) do
    if truthy?(condition), do: merge(attrs), else: %{}
  end

  def missing_value, do: @missing

  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(""), do: false
  defp truthy?([]), do: false
  defp truthy?(%{} = m), do: map_size(m) > 0
  defp truthy?(_), do: true

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
