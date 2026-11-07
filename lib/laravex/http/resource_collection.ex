defmodule Laravex.Http.ResourceCollection do
  @moduledoc """
  Laravel-style JSON API resource collection.

      defmodule App.Http.Resources.UserCollection do
        use Laravex.Http.ResourceCollection, collects: App.Http.Resources.UserResource

        def additional(_resources), do: %{meta: %{total_hint: "users"}}
      end

      UserCollection.make(users)
      UserCollection.make(paginator)

  Anonymous collections (Laravel `UserResource::collection($users)`):

      Laravex.Http.ResourceCollection.anonymous(UserResource, users) |> response()
  """

  defstruct collects: nil,
            resources: [],
            additional: %{},
            wrap: "data"

  defmacro __using__(opts) do
    collects = Keyword.fetch!(opts, :collects)

    quote do
      @collects unquote(collects)

      def collects, do: @collects
      def wrap, do: "data"
      def additional(_resources), do: %{}

      @doc "Build a collection struct from a list or paginator."
      def new(resources) do
        Laravex.Http.ResourceCollection.new(__MODULE__, resources)
      end

      @doc "Transform resources to the JSON envelope map."
      def to_map(resources) do
        Laravex.Http.ResourceCollection.to_map(__MODULE__, resources)
      end

      @doc "Return a JSON response for the collection."
      def make(resources) do
        Laravex.Http.ResourceCollection.respond(__MODULE__, resources)
      end

      defoverridable wrap: 0, additional: 1, to_map: 1
    end
  end

  @doc "Anonymous collection wrapping a resource module (Laravel `Resource::collection`)."
  def anonymous(collects_mod, resources) when is_atom(collects_mod) do
    extra =
      if function_exported?(collects_mod, :additional, 1) do
        collects_mod.additional(resources)
      else
        %{}
      end

    %__MODULE__{
      collects: collects_mod,
      resources: resources,
      additional: stringify_keys(extra),
      wrap: wrap_of(collects_mod)
    }
  end

  @doc "Named collection module → struct."
  def new(collection_mod, resources) when is_atom(collection_mod) do
    %__MODULE__{
      collects: collection_mod.collects(),
      resources: resources,
      additional: stringify_keys(collection_mod.additional(resources)),
      wrap: collection_mod.wrap()
    }
  end

  @doc "Laravel `->additional([...])` on a collection instance."
  def additional(%__MODULE__{} = collection, map) when is_map(map) do
    %{collection | additional: Map.merge(collection.additional || %{}, stringify_keys(map))}
  end

  @doc "Override wrap key on a collection instance."
  def wrap(%__MODULE__{} = collection, key), do: %{collection | wrap: key}

  @doc "Turn a collection struct into a JSON HTTP response."
  def response(%__MODULE__{} = collection) do
    data = map_resources(collection.collects, collection.resources)
    extra = collection.additional || %{}

    payload =
      case pagination_envelope(collection.resources, data) do
        nil ->
          wrap_data(collection.wrap, data)

        %{data: data, links: links, meta: meta} ->
          wrap_data(collection.wrap, data)
          |> Map.merge(%{"links" => stringify_keys(links), "meta" => stringify_keys(meta)})
      end

    Laravex.Http.Response.json(Map.merge(payload, extra))
  end

  @doc "Respond using a collection module + resources."
  def respond(collection_mod, resources) when is_atom(collection_mod) do
    collection_mod
    |> new(resources)
    |> response()
  end

  @doc "Envelope map for a collection module (without HTTP response)."
  def to_map(collection_mod, resources) when is_atom(collection_mod) do
    collects = collection_mod.collects()
    data = map_resources(collects, resources)
    extra = stringify_keys(collection_mod.additional(resources))

    case pagination_envelope(resources, data) do
      nil ->
        wrap_data(collection_mod.wrap(), data) |> Map.merge(extra)

      %{data: data, links: links, meta: meta} ->
        wrap_data(collection_mod.wrap(), data)
        |> Map.merge(%{"links" => stringify_keys(links), "meta" => stringify_keys(meta)})
        |> Map.merge(extra)
    end
  end

  defp map_resources(collects, resources) do
    resources
    |> unwrap_items()
    |> Enum.map(fn item ->
      if function_exported?(collects, :to_map, 1) do
        collects.to_map(item)
      else
        item
      end
    end)
  end

  defp unwrap_items(%{data: data}), do: List.wrap(data)
  defp unwrap_items(%{"data" => data}), do: List.wrap(data)
  defp unwrap_items(list) when is_list(list), do: list
  defp unwrap_items(other), do: List.wrap(other)

  defp pagination_envelope(resources, mapped_data) when is_map(resources) do
    if pager?(resources) do
      total = Map.get(resources, :total) || Map.get(resources, "total") || 0
      per_page = Map.get(resources, :per_page) || Map.get(resources, "per_page") || 15
      current = Laravex.Http.Paginator.current_page(resources)
      last = Laravex.Http.Paginator.last_page(resources)
      path = Laravex.Http.Paginator.pager_path(resources)

      %{
        data: mapped_data,
        links: %{
          first: Laravex.Http.Paginator.page_url(resources, 1, path),
          last: Laravex.Http.Paginator.page_url(resources, last, path),
          prev:
            if(current > 1,
              do: Laravex.Http.Paginator.page_url(resources, current - 1, path),
              else: nil
            ),
          next:
            if(current < last,
              do: Laravex.Http.Paginator.page_url(resources, current + 1, path),
              else: nil
            )
        },
        meta: %{
          current_page: current,
          from: if(total == 0, do: nil, else: (current - 1) * per_page + 1),
          last_page: last,
          path: path,
          per_page: per_page,
          to: min(current * per_page, total),
          total: total
        }
      }
    else
      nil
    end
  end

  defp pagination_envelope(_, _), do: nil

  defp pager?(map) when is_map(map) do
    has_data? = Map.has_key?(map, :data) or Map.has_key?(map, "data")

    has_meta? =
      Map.has_key?(map, :total) or Map.has_key?(map, "total") or
        Map.has_key?(map, :per_page) or Map.has_key?(map, "per_page") or
        Map.has_key?(map, :current_page) or Map.has_key?(map, "current_page")

    has_data? and has_meta?
  end

  defp wrap_data(false, data), do: %{"data" => data}
  defp wrap_data(nil, data), do: %{"data" => data}

  defp wrap_data(key, data) do
    %{to_string(key) => data}
  end

  defp wrap_of(mod) do
    if function_exported?(mod, :wrap, 0), do: mod.wrap(), else: "data"
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {to_string(k), if(is_map(v) and not is_struct(v), do: stringify_keys(v), else: v)}
    end)
  end
end
