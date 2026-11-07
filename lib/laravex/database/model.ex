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
        attrs =
          model
          |> Map.from_struct()
          |> Map.drop([:__struct__, :id, :__relations__])
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new(fn {k, v} -> {to_string(k), v} end)

        create(attrs)
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
            |> then(&Laravex.Database.Model.apply_mutators(__MODULE__, &1))
            |> then(&Laravex.Database.Model.apply_persist_casts(&1, __MODULE__))
            |> Map.put("updated_at", now)
          end

        Laravex.Database.Query.table(table_name())
        |> Laravex.Database.Query.where("id", id)
        |> Laravex.Database.Query.update(attrs)

        saved = find(id, with_trashed: true)
        if saved, do: Laravex.Database.Model.touch_parents(saved), else: saved
        saved
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

      def paginate(per_page \\ 15, page \\ 1, opts \\ []) do
        Laravex.Database.Model.paginate(__MODULE__, per_page, page, opts)
      end

      def has_many(name, related, foreign_key \\ nil) do
        foreign_key =
          foreign_key || Macro.underscore(__MODULE__ |> Module.split() |> List.last()) <> "_id"

        {:has_many, name, related, foreign_key}
      end

      def has_one(name, related, foreign_key \\ nil) do
        foreign_key =
          foreign_key || Macro.underscore(__MODULE__ |> Module.split() |> List.last()) <> "_id"

        {:has_one, name, related, foreign_key}
      end

      def belongs_to(name, related, foreign_key \\ nil) do
        foreign_key = foreign_key || to_string(name) <> "_id"
        {:belongs_to, name, related, foreign_key}
      end

      def belongs_to_many(name, related, pivot \\ nil, foreign_pivot_key \\ nil, related_pivot_key \\ nil) do
        owner_base = Macro.underscore(__MODULE__ |> Module.split() |> List.last())
        related_base = Macro.underscore(related |> Module.split() |> List.last())

        pivot =
          pivot ||
            [owner_base, related_base]
            |> Enum.sort()
            |> Enum.join("_")

        foreign_pivot_key = foreign_pivot_key || owner_base <> "_id"
        related_pivot_key = related_pivot_key || related_base <> "_id"

        {:belongs_to_many, name, related, pivot, foreign_pivot_key, related_pivot_key}
      end

      def load(%__MODULE__{} = model, relation_name)
          when is_atom(relation_name) or is_binary(relation_name) do
        Laravex.Database.Model.load_relation(model, __MODULE__, relation_name)
      end

      def with(models, relations) when is_list(models) do
        Laravex.Database.Model.with_relations(models, __MODULE__, relations)
      end

      def with_count(models, relations) when is_list(models) do
        Laravex.Database.Model.with_counts(models, __MODULE__, relations)
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

      def touch(%__MODULE__{} = model, attr \\ "updated_at") do
        Laravex.Database.Model.touch(model, attr)
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

  def paginate(mod, per_page, page, opts \\ []) when page >= 1 do
    total = Laravex.Database.Query.count(mod.query())
    offset = (page - 1) * per_page

    data =
      mod.query()
      |> Laravex.Database.Query.limit(per_page)
      |> Laravex.Database.Query.offset(offset)
      |> Laravex.Database.Query.get()
      |> Enum.map(&mod.from_row/1)

    path = Keyword.get(opts, :path, "/")

    query =
      opts
      |> Keyword.get(:query, %{})
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.delete("page")

    %{
      data: data,
      total: total,
      per_page: per_page,
      current_page: page,
      last_page: max(1, ceil(total / max(per_page, 1))),
      path: path,
      query: query
    }
  end

  def with_relations(models, owner_mod, relations) do
    rels = List.wrap(relations)

    Enum.reduce(rels, models, fn rel, acc ->
      batch_load_relation(acc, owner_mod, rel)
    end)
  end

  def with_counts(models, owner_mod, relations) do
    rels = List.wrap(relations)

    Enum.reduce(rels, models, fn rel, acc ->
      batch_count_relation(acc, owner_mod, rel)
    end)
  end

  def load_relation(model, owner_mod, relation_name, opts \\ []) do
    [loaded] = batch_load_relation([model], owner_mod, relation_name, opts)
    loaded
  end

  def batch_load_relation(models, owner_mod, relation_name, opts \\ [])
  def batch_load_relation([], _owner_mod, _relation_name, _opts), do: []

  def batch_load_relation(models, owner_mod, relation_name, opts) do
    relation_name = to_string(relation_name)
    query_opts = Keyword.take(opts, [:with_trashed, :only_trashed])
    rel_def = relation_def(owner_mod, relation_name)

    case rel_def do
      {:has_many, _name, related, fk} ->
        ids = Enum.map(models, & &1.id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

        grouped =
          if ids == [] do
            %{}
          else
            related.query(query_opts)
            |> Laravex.Database.Query.where_in(fk, ids)
            |> Laravex.Database.Query.get()
            |> Enum.map(&related.from_row/1)
            |> Enum.group_by(fn row -> Map.get(row, String.to_atom(fk)) end)
          end

        Enum.map(models, fn model ->
          put_loaded(model, relation_name, Map.get(grouped, model.id, []))
        end)

      {:has_one, _name, related, fk} ->
        ids = Enum.map(models, & &1.id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

        by_owner =
          if ids == [] do
            %{}
          else
            related.query(query_opts)
            |> Laravex.Database.Query.where_in(fk, ids)
            |> Laravex.Database.Query.get()
            |> Enum.map(&related.from_row/1)
            |> Enum.reduce(%{}, fn row, acc ->
              owner_id = Map.get(row, String.to_atom(fk))
              Map.put_new(acc, owner_id, row)
            end)
          end

        Enum.map(models, fn model ->
          put_loaded(model, relation_name, Map.get(by_owner, model.id))
        end)

      {:belongs_to, _name, related, fk} ->
        fk_atom = String.to_atom(fk)

        parent_ids =
          models
          |> Enum.map(&Map.get(&1, fk_atom))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        by_id =
          if parent_ids == [] do
            %{}
          else
            related.query(query_opts)
            |> Laravex.Database.Query.where_in("id", parent_ids)
            |> Laravex.Database.Query.get()
            |> Enum.map(&related.from_row/1)
            |> Map.new(fn row -> {row.id, row} end)
          end

        Enum.map(models, fn model ->
          put_loaded(model, relation_name, Map.get(by_id, Map.get(model, fk_atom)))
        end)

      {:belongs_to_many, _name, related, pivot, fk, rk} ->
        ids = Enum.map(models, & &1.id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

        pivot_rows =
          if ids == [] do
            []
          else
            Laravex.Database.Query.table(pivot)
            |> Laravex.Database.Query.where_in(fk, ids)
            |> Laravex.Database.Query.get()
          end

        related_ids =
          pivot_rows
          |> Enum.map(fn row -> Map.get(row, rk) || Map.get(row, String.to_atom(rk)) end)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        by_related =
          if related_ids == [] do
            %{}
          else
            related.query(query_opts)
            |> Laravex.Database.Query.where_in("id", related_ids)
            |> Laravex.Database.Query.get()
            |> Enum.map(&related.from_row/1)
            |> Map.new(fn row -> {row.id, row} end)
          end

        grouped =
          Enum.reduce(pivot_rows, %{}, fn row, acc ->
            owner_id = Map.get(row, fk) || Map.get(row, String.to_atom(fk))
            related_id = Map.get(row, rk) || Map.get(row, String.to_atom(rk))
            child = Map.get(by_related, related_id)
            if owner_id && child, do: Map.update(acc, owner_id, [child], &(&1 ++ [child])), else: acc
          end)

        Enum.map(models, fn model ->
          put_loaded(model, relation_name, Map.get(grouped, model.id, []))
        end)

      _ ->
        models
    end
  end

  def batch_count_relation(models, owner_mod, relation_name) do
    relation_name = to_string(relation_name)
    count_key = relation_name <> "_count"
    rel_def = relation_def(owner_mod, relation_name)
    ids = Enum.map(models, & &1.id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    counts =
      case rel_def do
        {:has_many, _n, related, fk} when ids != [] ->
          related.query()
          |> Laravex.Database.Query.where_in(fk, ids)
          |> Laravex.Database.Query.get()
          |> Enum.reduce(%{}, fn row, acc ->
            owner_id = Map.get(row, fk) || Map.get(row, String.to_atom(fk))
            Map.update(acc, owner_id, 1, &(&1 + 1))
          end)

        {:has_one, _n, related, fk} when ids != [] ->
          related.query()
          |> Laravex.Database.Query.where_in(fk, ids)
          |> Laravex.Database.Query.get()
          |> Enum.reduce(%{}, fn row, acc ->
            owner_id = Map.get(row, fk) || Map.get(row, String.to_atom(fk))
            Map.put_new(acc, owner_id, 1)
          end)

        {:belongs_to_many, _n, _related, pivot, fk, _rk} when ids != [] ->
          Laravex.Database.Query.table(pivot)
          |> Laravex.Database.Query.where_in(fk, ids)
          |> Laravex.Database.Query.get()
          |> Enum.reduce(%{}, fn row, acc ->
            owner_id = Map.get(row, fk) || Map.get(row, String.to_atom(fk))
            Map.update(acc, owner_id, 1, &(&1 + 1))
          end)

        _ ->
          %{}
      end

    Enum.map(models, fn model ->
      put_loaded(model, count_key, Map.get(counts, model.id, 0))
    end)
  end

  defp relation_def(owner_mod, relation_name) do
    relations =
      if function_exported?(owner_mod, :relations, 0) do
        owner_mod.relations()
      else
        []
      end

    Laravex.Eloquex.Relation.find_def(relations, relation_name)
  end

  defp put_loaded(model, name, value) do
    Process.put(relation_key(model, name), {:loaded, value})
    model
  end

  def get_relation(model, name) do
    case Process.get(relation_key(model, name)) do
      {:loaded, value} -> value
      _ -> nil
    end
  end

  def relation_loaded?(model, name) do
    match?({:loaded, _}, Process.get(relation_key(model, name)))
  end

  defp relation_key(model, name) do
    {:laravex_relation, {model.__struct__, Map.get(model, :id), to_string(name)}}
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
    mod = model.__struct__
    accessor = :"get_#{key_atom}_attribute"

    cond do
      function_exported?(mod, accessor, 1) ->
        value = if Map.has_key?(model, key_atom), do: Map.get(model, key_atom), else: nil
        apply(mod, accessor, [value])

      Map.has_key?(model, key_atom) ->
        cast_out(mod, to_string(key), Map.get(model, key_atom))

      relation_loaded?(model, key) ->
        get_relation(model, key)

      true ->
        nil
    end
  end

  def apply_persist_casts(attrs, mod) when is_map(attrs) do
    casts = if function_exported?(mod, :casts, 0), do: stringify(mod.casts()), else: %{}

    Map.new(attrs, fn {k, v} ->
      key = to_string(k)
      {key, cast_one(Map.get(casts, key), v)}
    end)
  end

  def touch(model, attr \\ "updated_at")

  def touch(%{id: nil} = model, _attr), do: model

  def touch(%{__struct__: mod, id: id} = model, attr) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    attr = to_string(attr)

    Laravex.Database.Query.table(mod.table_name())
    |> Laravex.Database.Query.where("id", id)
    |> Laravex.Database.Query.update(%{attr => now, "updated_at" => now})

    touched = Map.put(model, String.to_atom(attr), now) |> Map.put(:updated_at, now)
    sync_original(touched)
    touch_parents(touched)
    touched
  end

  def touch_parents(model) do
    mod = model.__struct__

    if function_exported?(mod, :touches, 0) do
      Enum.each(List.wrap(mod.touches()), fn name ->
        case Laravex.Eloquex.Relation.for(model, name) do
          %Laravex.Eloquex.Relation.BelongsTo{} = rel ->
            case Laravex.Eloquex.Relation.BelongsTo.get(rel) do
              %{id: _} = parent -> touch(parent)
              _ -> :ok
            end

          _ ->
            :ok
        end
      end)
    end

    model
  end

  def apply_mutators(mod, attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} ->
      key = to_string(k)
      mutator = :"set_#{key}_attribute"

      if function_exported?(mod, mutator, 1) do
        {key, apply(mod, mutator, [v])}
      else
        {key, v}
      end
    end)
  end

  defp cast_out(mod, key, value) do
    casts = if function_exported?(mod, :casts, 0), do: stringify(mod.casts()), else: %{}

    case Map.get(casts, key) do
      :boolean -> cast_one(:boolean, value)
      :json -> cast_one(:json, value)
      :array -> cast_one(:array, value)
      :datetime -> value
      :hashed -> value
      _ -> value
    end
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

  @system_attrs ~w(id created_at updated_at email_verified_at remember_token deleted_at)

  def cast_attrs(mod, attrs) do
    casts = if function_exported?(mod, :casts, 0), do: mod.casts(), else: %{}
    attrs = Enum.filter(attrs, fn {k, _} -> fillable?(mod, k) end)

    Map.new(attrs, fn {k, v} ->
      {k, cast_one(Map.get(casts, k), v)}
    end)
  end

  def fillable?(mod, key) do
    key = to_string(key)

    cond do
      key in @system_attrs ->
        true

      function_exported?(mod, :fillable, 0) ->
        key in Enum.map(mod.fillable(), &to_string/1)

      function_exported?(mod, :guarded, 0) ->
        guarded = Enum.map(mod.guarded(), &to_string/1)
        "*" not in guarded and key not in guarded

      true ->
        # Eloquex default: unguarded mass assignment when neither fillable nor guarded
        true
    end
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
