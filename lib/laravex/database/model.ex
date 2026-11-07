defmodule Laravex.Database.Model do
  @moduledoc """
  Compatibility ActiveRecord base (prefer `Laravex.Eloquex.Model` — Eloquex).

  Soft deletes, relations, pagination, scopes, accessors/mutators, dirty tracking.
  Use with `use Laravex.Database.Model, table: "users"` or `soft_deletes: true`.
  """

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    soft_deletes = Keyword.get(opts, :soft_deletes, false)

    quote do
      def table_name, do: unquote(table)
      def soft_deletes?, do: unquote(soft_deletes)

      def new(attrs \\ %{}) when is_map(attrs) do
        attrs = Laravex.Database.Model.stringify(attrs)
        casted = Laravex.Database.Model.cast_attrs(__MODULE__, attrs)
        mutated = Laravex.Database.Model.apply_mutators(__MODULE__, casted)
        model = struct(__MODULE__, Laravex.Database.Model.atomize(mutated))
        Laravex.Database.Model.sync_original(model)
      end

      def query(opts \\ []) do
        q = Laravex.Database.Model.__query_base__(__MODULE__, unquote(soft_deletes), opts)

        if Keyword.get(opts, :without_global_scopes, false) do
          q
        else
          Laravex.Database.Model.apply_global_scopes(__MODULE__, q)
        end
      end

      def scope(q, name, args \\ []) when is_atom(name) do
        apply(__MODULE__, :"scope_#{name}", [q | List.wrap(args)])
      end

      def all(opts \\ []) do
        query(opts) |> Laravex.Database.Query.get() |> Enum.map(&from_row/1)
      end

      def find(id, opts \\ []) do
        case query(opts) |> Laravex.Database.Query.where("id", id) |> Laravex.Database.Query.first() do
          nil -> nil
          row -> from_row(row)
        end
      end

      def find_by_email(email) do
        case query() |> Laravex.Database.Query.where("email", email) |> Laravex.Database.Query.first() do
          nil -> nil
          row -> from_row(row)
        end
      end

      def where(column, value) do
        query()
        |> Laravex.Database.Query.where(column, value)
        |> Laravex.Database.Query.get()
        |> Enum.map(&from_row/1)
      end

      def with_trashed, do: all(with_trashed: true)
      def only_trashed, do: all(only_trashed: true)

      def create(attrs) when is_map(attrs) do
        model = new(attrs)
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        row =
          model
          |> Map.from_struct()
          |> Map.drop([:__struct__, :id])
          |> Enum.reject(fn {k, v} -> is_nil(v) or k in [:__relations__] end)
          |> Map.new(fn {k, v} -> {to_string(k), v} end)
          |> Map.put("created_at", now)
          |> Map.put("updated_at", now)

        id = Laravex.Database.Query.insert(table_name(), row)
        find(id)
      end

      def save(%__MODULE__{id: nil} = model) do
        create(Map.from_struct(model))
      end

      def save(%__MODULE__{id: id} = model) do
        now = DateTime.utc_now() |> DateTime.to_iso8601()
        changes = Laravex.Database.Model.get_changes(model)

        attrs =
          if map_size(changes) == 0 do
            %{"updated_at" => now}
          else
            changes
            |> Map.new(fn {k, v} -> {to_string(k), v} end)
            |> Map.put("updated_at", now)
          end

        Laravex.Database.Query.table(table_name())
        |> Laravex.Database.Query.where("id", id)
        |> Laravex.Database.Query.update(attrs)

        find(id, with_trashed: true)
      end

      def delete(%__MODULE__{id: id} = model) do
        if unquote(soft_deletes) do
          now = DateTime.utc_now() |> DateTime.to_iso8601()

          Laravex.Database.Query.table(table_name())
          |> Laravex.Database.Query.where("id", id)
          |> Laravex.Database.Query.update(%{"deleted_at" => now})

          :ok
        else
          force_delete(model)
        end
      end

      def force_delete(%__MODULE__{id: id}) do
        Laravex.Database.Query.table(table_name())
        |> Laravex.Database.Query.where("id", id)
        |> Laravex.Database.Query.delete()

        :ok
      end

      def restore(%__MODULE__{id: id}) do
        if unquote(soft_deletes) do
          Laravex.Database.Query.table(table_name())
          |> Laravex.Database.Query.where("id", id)
          |> Laravex.Database.Query.update(%{"deleted_at" => nil})

          find(id)
        else
          find(id)
        end
      end

      def paginate(per_page \\ 15, page \\ 1) do
        Laravex.Database.Model.paginate(__MODULE__, per_page, page)
      end

      def has_many(name, related, foreign_key \\ nil) do
        foreign_key =
          foreign_key || Macro.underscore(__MODULE__ |> Module.split() |> List.last()) <> "_id"

        {:has_many, name, related, foreign_key}
      end

      def belongs_to(name, related, foreign_key \\ nil) do
        foreign_key = foreign_key || to_string(name) <> "_id"
        {:belongs_to, name, related, foreign_key}
      end

      def load(%__MODULE__{} = model, relation_name)
          when is_atom(relation_name) or is_binary(relation_name) do
        Laravex.Database.Model.load_relation(model, __MODULE__, relation_name)
      end

      def with(models, relations) when is_list(models) do
        Laravex.Database.Model.with_relations(models, __MODULE__, relations)
      end

      def from_row(row) when is_map(row) do
        new(row)
      end

      def get_attribute(%__MODULE__{} = model, key) do
        Laravex.Database.Model.get_attribute(model, key)
      end

      def is_dirty?(%__MODULE__{} = model, attr \\ nil) do
        Laravex.Database.Model.is_dirty?(model, attr)
      end

      def get_changes(%__MODULE__{} = model) do
        Laravex.Database.Model.get_changes(model)
      end

      def to_map(%__MODULE__{} = model) do
        Laravex.Database.Model.to_map(model)
      end

      defoverridable new: 0, new: 1, find_by_email: 1
    end
  end

  def __query_base__(mod, soft_deletes, opts \\ []) do
    q = Laravex.Database.Query.table(mod.table_name())

    if soft_deletes do
      cond do
        Keyword.get(opts, :with_trashed, false) ->
          q

        Keyword.get(opts, :only_trashed, false) ->
          Laravex.Database.Query.where_not_null(q, "deleted_at")

        true ->
          Laravex.Database.Query.where_null(q, "deleted_at")
      end
    else
      q
    end
  end

  def apply_global_scopes(mod, q) do
    if function_exported?(mod, :__global_scopes__, 0) do
      Enum.reduce(mod.__global_scopes__() || [], q, fn
        {_name, fun}, acc when is_function(fun, 1) -> fun.(acc)
        fun, acc when is_function(fun, 1) -> fun.(acc)
        _, acc -> acc
      end)
    else
      q
    end
  end

  def paginate(mod, per_page, page) when page >= 1 do
    total = Laravex.Database.Query.count(mod.query())
    offset = (page - 1) * per_page

    data =
      mod.query()
      |> Laravex.Database.Query.limit(per_page)
      |> Laravex.Database.Query.offset(offset)
      |> Laravex.Database.Query.get()
      |> Enum.map(&mod.from_row/1)

    %{
      data: data,
      total: total,
      per_page: per_page,
      current_page: page,
      last_page: max(1, ceil(total / max(per_page, 1)))
    }
  end

  def with_relations(models, owner_mod, relations) do
    rels = List.wrap(relations)

    Enum.map(models, fn model ->
      Enum.reduce(rels, model, fn rel, acc -> load_relation(acc, owner_mod, rel) end)
    end)
  end

  def load_relation(model, owner_mod, relation_name) do
    relation_name = to_string(relation_name)

    relations =
      if function_exported?(owner_mod, :relations, 0) do
        owner_mod.relations()
      else
        []
      end

    case Enum.find(relations, fn
           {_, name, _, _} -> to_string(name) == relation_name
           _ -> false
         end) do
      {:has_many, _name, related, fk} ->
        rows = related.where(fk, model.id)
        put_loaded(model, relation_name, rows)

      {:belongs_to, _name, related, fk} ->
        fk_atom = String.to_atom(fk)
        fk_val = Map.get(model, fk_atom)
        row = if fk_val, do: related.find(fk_val), else: nil
        put_loaded(model, relation_name, row)

      _ ->
        model
    end
  end

  defp put_loaded(model, name, value) do
    key = {model.__struct__, Map.get(model, :id), name}
    Process.put({:laravex_relation, key}, value)
    model
  end

  def get_relation(model, name) do
    key = {model.__struct__, Map.get(model, :id), to_string(name)}
    Process.get({:laravex_relation, key})
  end

  def sync_original(model) do
    key = original_key(model)
    Process.put(key, Map.from_struct(model) |> Map.drop([:__struct__]))
    model
  end

  def is_dirty?(model, nil) do
    map_size(get_changes(model)) > 0
  end

  def is_dirty?(model, attr) do
    Map.has_key?(get_changes(model), String.to_atom(to_string(attr)))
  end

  def get_changes(model) do
    original = Process.get(original_key(model), %{})
    current = Map.from_struct(model) |> Map.drop([:__struct__])

    current
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      if Map.get(original, k) != v and k not in [:__relations__] do
        Map.put(acc, k, v)
      else
        acc
      end
    end)
  end

  def get_attribute(model, key) do
    key_atom = String.to_atom(to_string(key))
    value = Map.get(model, key_atom)
    mod = model.__struct__
    accessor = :"get_#{key_atom}_attribute"

    if function_exported?(mod, accessor, 1) do
      apply(mod, accessor, [value])
    else
      value
    end
  end

  def apply_mutators(mod, attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} ->
      mutator = :"set_#{k}_attribute"

      if function_exported?(mod, mutator, 1) do
        {k, apply(mod, mutator, [v])}
      else
        {k, v}
      end
    end)
  end

  def to_map(model) do
    mod = model.__struct__
    hidden = if function_exported?(mod, :hidden, 0), do: Enum.map(mod.hidden(), &to_string/1), else: []
    appends = if function_exported?(mod, :appends, 0), do: mod.appends(), else: []

    base =
      model
      |> Map.from_struct()
      |> Enum.reject(fn {k, _} -> to_string(k) in hidden or k == :__relations__ end)
      |> Map.new(fn {k, v} -> {to_string(k), get_attribute(model, k) || v} end)

    Enum.reduce(List.wrap(appends), base, fn key, acc ->
      Map.put(acc, to_string(key), get_attribute(model, key))
    end)
  end

  defp original_key(model), do: {:laravex_original, model.__struct__, Map.get(model, :id)}

  def stringify(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  def atomize(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(to_string(k)), v} end)
  end

  def cast_attrs(mod, attrs) do
    casts = if function_exported?(mod, :casts, 0), do: mod.casts(), else: %{}
    fillable = if function_exported?(mod, :fillable, 0), do: mod.fillable(), else: Map.keys(attrs)

    attrs
    |> Enum.filter(fn {k, _} ->
      k in fillable or
        k in ["id", "created_at", "updated_at", "email_verified_at", "remember_token", "deleted_at"]
    end)
    |> Map.new(fn {k, v} ->
      {k, cast_one(Map.get(casts, k), v)}
    end)
  end

  defp cast_one(:hashed, v) when is_binary(v) do
    if String.starts_with?(v, "pbkdf2:") or String.starts_with?(v, "hashed:"),
      do: v,
      else: Laravex.Hashing.Hash.make(v)
  end

  defp cast_one(:datetime, nil), do: nil
  defp cast_one(:datetime, %DateTime{} = v), do: DateTime.to_iso8601(v)
  defp cast_one(:datetime, v), do: v

  defp cast_one(:boolean, v) when v in [true, 1, "1", "true", "on", "yes"], do: true
  defp cast_one(:boolean, v) when v in [false, 0, "0", "false", "off", "no", nil], do: false
  defp cast_one(:boolean, _), do: false

  defp cast_one(:array, v) when is_list(v), do: v
  defp cast_one(:array, v) when is_binary(v) do
    case Laravex.Support.JSON.decode(v) do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end
  defp cast_one(:array, nil), do: []
  defp cast_one(:array, _), do: []

  defp cast_one(:json, v) when is_map(v) or is_list(v), do: v
  defp cast_one(:json, v) when is_binary(v) do
    case Laravex.Support.JSON.decode(v) do
      {:ok, decoded} -> decoded
      _ -> v
    end
  end
  defp cast_one(:json, nil), do: nil

  defp cast_one(_, v), do: v
end
