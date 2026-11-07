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

      def find_or_fail(id, opts \\ []) do
        case find(id, opts) do
          nil -> raise Laravex.Database.ModelNotFoundException, model: __MODULE__, id: id
          model -> model
        end
      end

      def first(opts \\ []) do
        case query(opts) |> Laravex.Database.Query.first() do
          nil -> nil
          row -> from_row(row)
        end
      end

      def first_or_fail(opts \\ []) do
        case first(opts) do
          nil -> raise Laravex.Database.ModelNotFoundException, model: __MODULE__, id: nil
          model -> model
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

      def where_has(relation) when is_atom(relation) or is_binary(relation) do
        Laravex.Database.Model.where_has(__MODULE__, query(), relation, nil)
      end

      def where_has(%Laravex.Database.Query{} = q, relation) do
        Laravex.Database.Model.where_has(__MODULE__, q, relation, nil)
      end

      def where_has(relation, constraint)
          when (is_atom(relation) or is_binary(relation)) and
                 (is_function(constraint, 1) or is_nil(constraint)) do
        Laravex.Database.Model.where_has(__MODULE__, query(), relation, constraint)
      end

      def where_has(%Laravex.Database.Query{} = q, relation, constraint) do
        Laravex.Database.Model.where_has(__MODULE__, q, relation, constraint)
      end

      def or_where_has(relation) when is_atom(relation) or is_binary(relation) do
        Laravex.Database.Model.or_where_has(__MODULE__, query(), relation, nil)
      end

      def or_where_has(%Laravex.Database.Query{} = q, relation) do
        Laravex.Database.Model.or_where_has(__MODULE__, q, relation, nil)
      end

      def or_where_has(relation, constraint)
          when (is_atom(relation) or is_binary(relation)) and
                 (is_function(constraint, 1) or is_nil(constraint)) do
        Laravex.Database.Model.or_where_has(__MODULE__, query(), relation, constraint)
      end

      def or_where_has(%Laravex.Database.Query{} = q, relation, constraint) do
        Laravex.Database.Model.or_where_has(__MODULE__, q, relation, constraint)
      end

      def where_doesnt_have(relation) when is_atom(relation) or is_binary(relation) do
        Laravex.Database.Model.where_doesnt_have(__MODULE__, query(), relation, nil)
      end

      def where_doesnt_have(%Laravex.Database.Query{} = q, relation) do
        Laravex.Database.Model.where_doesnt_have(__MODULE__, q, relation, nil)
      end

      def where_doesnt_have(relation, constraint)
          when (is_atom(relation) or is_binary(relation)) and
                 (is_function(constraint, 1) or is_nil(constraint)) do
        Laravex.Database.Model.where_doesnt_have(__MODULE__, query(), relation, constraint)
      end

      def where_doesnt_have(%Laravex.Database.Query{} = q, relation, constraint) do
        Laravex.Database.Model.where_doesnt_have(__MODULE__, q, relation, constraint)
      end

      def or_where_doesnt_have(relation) when is_atom(relation) or is_binary(relation) do
        Laravex.Database.Model.or_where_doesnt_have(__MODULE__, query(), relation, nil)
      end

      def or_where_doesnt_have(%Laravex.Database.Query{} = q, relation) do
        Laravex.Database.Model.or_where_doesnt_have(__MODULE__, q, relation, nil)
      end

      def or_where_doesnt_have(relation, constraint)
          when (is_atom(relation) or is_binary(relation)) and
                 (is_function(constraint, 1) or is_nil(constraint)) do
        Laravex.Database.Model.or_where_doesnt_have(__MODULE__, query(), relation, constraint)
      end

      def or_where_doesnt_have(%Laravex.Database.Query{} = q, relation, constraint) do
        Laravex.Database.Model.or_where_doesnt_have(__MODULE__, q, relation, constraint)
      end

      def has(relation) when is_atom(relation) or is_binary(relation) do
        where_has(relation)
      end

      def has(%Laravex.Database.Query{} = q, relation) do
        where_has(q, relation)
      end

      def doesnt_have(relation) when is_atom(relation) or is_binary(relation) do
        where_doesnt_have(relation)
      end

      def doesnt_have(%Laravex.Database.Query{} = q, relation) do
        where_doesnt_have(q, relation)
      end

      def load_missing(%__MODULE__{} = model, relations) do
        Laravex.Database.Model.load_missing(model, __MODULE__, relations)
      end

      def load_missing(models, relations) when is_list(models) do
        Laravex.Database.Model.load_missing(models, __MODULE__, relations)
      end

      def load_count(%__MODULE__{} = model, relations) do
        Laravex.Database.Model.load_count(model, __MODULE__, relations)
      end

      def load_count(models, relations) when is_list(models) do
        Laravex.Database.Model.load_count(models, __MODULE__, relations)
      end

      def without(%__MODULE__{} = model, relations) do
        Laravex.Database.Model.without(model, relations)
      end

      def upsert(rows, unique_by, update \\ nil) do
        Laravex.Database.Query.upsert(table_name(), List.wrap(rows), unique_by, update)
      end

      def insert_or_ignore(rows) do
        Laravex.Database.Query.insert_or_ignore(table_name(), rows)
      end

      def with_trashed, do: all(with_trashed: true)
      def only_trashed, do: all(only_trashed: true)

      def create(attrs) when is_map(attrs) do
        Laravex.Database.Model.perform_create(__MODULE__, attrs)
      end

      def save(%__MODULE__{} = model) do
        Laravex.Database.Model.perform_save(__MODULE__, model)
      end

      def save_quietly(%__MODULE__{} = model) do
        Laravex.Database.Model.without_events(fn -> save(model) end)
      end

      def delete(%__MODULE__{} = model) do
        Laravex.Database.Model.perform_delete(__MODULE__, model, unquote(soft_deletes))
      end

      def force_delete(%__MODULE__{} = model) do
        Laravex.Database.Model.perform_force_delete(__MODULE__, model)
      end

      def restore(%__MODULE__{} = model) do
        Laravex.Database.Model.perform_restore(__MODULE__, model, unquote(soft_deletes))
      end

      @doc "True when the model has a non-nil `deleted_at` (Laravel `trashed()`)."
      def trashed?(%__MODULE__{} = model) do
        if unquote(soft_deletes) do
          deleted = Laravex.Database.Model.get_attribute(model, "deleted_at")
          not is_nil(deleted) and deleted != ""
        else
          false
        end
      end

      def paginate(per_page \\ 15, page \\ 1, opts \\ []) do
        Laravex.Database.Model.paginate(__MODULE__, per_page, page, opts)
      end

      def simple_paginate(per_page \\ 15, page \\ 1, opts \\ []) do
        Laravex.Database.Model.simple_paginate(__MODULE__, per_page, page, opts)
      end

      def cursor_paginate(per_page \\ 15, opts \\ []) do
        Laravex.Database.Model.cursor_paginate(__MODULE__, per_page, opts)
      end

      def chunk(size, fun) when is_integer(size) and is_function(fun, 1) do
        Laravex.Database.Query.chunk(query(), size, fn rows ->
          fun.(Enum.map(rows, &from_row/1))
        end)
      end

      def chunk_by_id(size, fun, opts \\ []) when is_integer(size) and is_function(fun, 1) do
        Laravex.Database.Query.chunk_by_id(query(), size, fn rows ->
          fun.(Enum.map(rows, &from_row/1))
        end, opts)
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

      def belongs_to(name, related, foreign_key \\ nil, opts \\ []) do
        foreign_key = foreign_key || to_string(name) <> "_id"

        case Keyword.get(opts, :with_default) do
          nil -> {:belongs_to, name, related, foreign_key}
          default -> {:belongs_to, name, related, foreign_key, default}
        end
      end

      def belongs_to_many(name, related, pivot \\ nil, foreign_pivot_key \\ nil, related_pivot_key_or_opts \\ nil, opts \\ []) do
        owner_base = Macro.underscore(__MODULE__ |> Module.split() |> List.last())
        related_base = Macro.underscore(related |> Module.split() |> List.last())

        {related_pivot_key, opts} =
          cond do
            is_list(related_pivot_key_or_opts) and related_pivot_key_or_opts != [] and
                Keyword.keyword?(related_pivot_key_or_opts) ->
              {nil, related_pivot_key_or_opts}

            is_binary(related_pivot_key_or_opts) ->
              {related_pivot_key_or_opts, opts}

            true ->
              {nil, opts}
          end

        pivot =
          pivot ||
            [owner_base, related_base]
            |> Enum.sort()
            |> Enum.join("_")

        foreign_pivot_key = foreign_pivot_key || owner_base <> "_id"
        related_pivot_key = related_pivot_key || related_base <> "_id"
        pivot_cols = Keyword.get(opts, :with_pivot, [])
        with_ts = Keyword.get(opts, :with_timestamps, true)

        {:belongs_to_many, name, related, pivot, foreign_pivot_key, related_pivot_key, pivot_cols,
         with_ts}
      end

      def morph_many(name, related, morph_name \\ "morph", morph_type \\ nil) do
        {:morph_many, name, related, to_string(morph_name), morph_type}
      end

      def morph_one(name, related, morph_name \\ "morph", morph_type \\ nil) do
        {:morph_one, name, related, to_string(morph_name), morph_type}
      end

      def morph_to(name, morph_name \\ nil) do
        morph = morph_name || to_string(name)
        {:morph_to, name, to_string(morph), nil}
      end

      def morph_to_many(name, related, pivot \\ nil, morph_name \\ "morph", related_key \\ nil) do
        related_base = Macro.underscore(related |> Module.split() |> List.last())
        owner_base = Macro.underscore(__MODULE__ |> Module.split() |> List.last())

        pivot =
          pivot ||
            [owner_base, related_base]
            |> Enum.sort()
            |> Enum.join("_")

        related_key = related_key || related_base <> "_id"
        {:morph_to_many, name, related, pivot, to_string(morph_name), related_key, nil}
      end

      def has_many_through(name, related, through, foreign_key \\ nil, second_key \\ nil) do
        owner_base = Macro.underscore(__MODULE__ |> Module.split() |> List.last())
        through_base = Macro.underscore(through |> Module.split() |> List.last())

        foreign_key = foreign_key || owner_base <> "_id"
        second_key = second_key || through_base <> "_id"
        {:has_many_through, name, related, through, foreign_key, second_key}
      end

      def has_one_through(name, related, through, foreign_key \\ nil, second_key \\ nil) do
        owner_base = Macro.underscore(__MODULE__ |> Module.split() |> List.last())
        through_base = Macro.underscore(through |> Module.split() |> List.last())

        foreign_key = foreign_key || owner_base <> "_id"
        second_key = second_key || through_base <> "_id"
        {:has_one_through, name, related, through, foreign_key, second_key}
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

      def refresh(%__MODULE__{id: id} = model) when not is_nil(id) do
        Laravex.Database.Model.refresh(model)
      end

      def fresh(%__MODULE__{id: id} = model, relations \\ []) when not is_nil(id) do
        Laravex.Database.Model.fresh(model, relations)
      end

      def replicate(%__MODULE__{} = model, except \\ []) do
        Laravex.Database.Model.replicate(model, except)
      end

      def increment(%__MODULE__{} = model, column, amount \\ 1) do
        Laravex.Database.Model.increment(model, column, amount)
      end

      def decrement(%__MODULE__{} = model, column, amount \\ 1) do
        Laravex.Database.Model.decrement(model, column, amount)
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

      def is_clean?(%__MODULE__{} = model, attr \\ nil) do
        Laravex.Database.Model.is_clean?(model, attr)
      end

      def get_changes(%__MODULE__{} = model) do
        Laravex.Database.Model.get_changes(model)
      end

      def get_original(%__MODULE__{} = model, attr \\ nil) do
        Laravex.Database.Model.get_original(model, attr)
      end

      def was_changed(%__MODULE__{} = model, attr \\ nil) do
        Laravex.Database.Model.was_changed?(model, attr)
      end

      def to_map(%__MODULE__{} = model) do
        Laravex.Database.Model.to_map(model)
      end

      def make_hidden(%__MODULE__{} = model, attrs) do
        Laravex.Database.Model.make_hidden(model, attrs)
      end

      def make_visible(%__MODULE__{} = model, attrs) do
        Laravex.Database.Model.make_visible(model, attrs)
      end

      def touch(%__MODULE__{} = model, attr \\ "updated_at") do
        Laravex.Database.Model.touch(model, attr)
      end

      defoverridable new: 0, new: 1, find_by_email: 1
    end
  end

  @lifecycle_events ~w(creating created updating updated deleting deleted restoring restored)a

  def without_events(fun) when is_function(fun, 0) do
    prev = Process.get(:laravex_without_events)

    try do
      Process.put(:laravex_without_events, true)
      fun.()
    after
      case prev do
        nil -> Process.delete(:laravex_without_events)
        v -> Process.put(:laravex_without_events, v)
      end
    end
  end

  def without_events?, do: truthy?(Process.get(:laravex_without_events))

  def prevent_lazy_loading?, do: truthy?(Process.get(:laravex_prevent_lazy_loading, Application.get_env(:laravex, :prevent_lazy_loading, false)))

  defp truthy?(v) when v in [false, nil, 0, "", "0"], do: false
  defp truthy?(_), do: true

  def perform_create(mod, attrs) when is_map(attrs) do
    model = mod.new(attrs)
    fire_before(mod, :creating, model)

    now = DateTime.utc_now() |> DateTime.to_iso8601()

    row =
      model
      |> Map.from_struct()
      |> Map.drop([:__struct__, :id])
      |> Enum.reject(fn {k, v} -> is_nil(v) or k in [:__relations__] end)
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("created_at", now)
      |> Map.put("updated_at", now)

    id = Laravex.Database.Query.insert(mod.table_name(), row)

    created =
      mod.find(id)
      |> case do
        nil -> model |> Map.put(:id, id)
        found -> found
      end

    fire_after(mod, :created, created)
    created
  end

  def perform_save(mod, %{id: nil} = model) do
    attrs =
      model
      |> Map.from_struct()
      |> Map.drop([:__struct__, :id, :__relations__])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new(fn {k, v} -> {to_string(k), v} end)

    perform_create(mod, attrs)
  end

  def perform_save(mod, %{id: id} = model) do
    fire_before(mod, :updating, model)

    now = DateTime.utc_now() |> DateTime.to_iso8601()
    changes = get_changes(model)

    attrs =
      if map_size(changes) == 0 do
        %{"updated_at" => now}
      else
        changes
        |> Map.new(fn {k, v} -> {to_string(k), v} end)
        |> then(&apply_mutators(mod, &1))
        |> then(&apply_persist_casts(&1, mod))
        |> Map.put("updated_at", now)
      end

    Laravex.Database.Query.table(mod.table_name())
    |> Laravex.Database.Query.where("id", id)
    |> Laravex.Database.Query.update(attrs)

    saved = mod.find(id, with_trashed: true)

    result =
      if saved do
        saved
        |> sync_was_changed(changes)
        |> touch_parents()
      else
        saved
      end

    if result, do: fire_after(mod, :updated, result)
    result
  end

  def perform_delete(mod, model, soft_deletes?) do
    fire_before(mod, :deleting, model)

    result =
      if soft_deletes? do
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        Laravex.Database.Query.table(mod.table_name())
        |> Laravex.Database.Query.where("id", model.id)
        |> Laravex.Database.Query.update(%{"deleted_at" => now})

        :ok
      else
        perform_force_delete(mod, model)
      end

    if soft_deletes?, do: fire_after(mod, :deleted, model)
    result
  end

  def perform_force_delete(mod, %{id: id} = model) do
    fire_before(mod, :deleting, model)

    Laravex.Database.Query.table(mod.table_name())
    |> Laravex.Database.Query.where("id", id)
    |> Laravex.Database.Query.delete()

    fire_after(mod, :deleted, model)
    :ok
  end

  def perform_restore(mod, model, soft_deletes?) do
    fire_before(mod, :restoring, model)

    result =
      if soft_deletes? do
        Laravex.Database.Query.table(mod.table_name())
        |> Laravex.Database.Query.where("id", model.id)
        |> Laravex.Database.Query.update(%{"deleted_at" => nil})

        mod.find(model.id)
      else
        mod.find(model.id)
      end

    if result, do: fire_after(mod, :restored, result)
    result
  end

  defp fire_before(mod, event, model) when event in @lifecycle_events do
    unless without_events?() do
      run_observers(mod, event, model)
      Laravex.Events.Dispatcher.dispatch(event, %{model: model, module: mod})
    end

    :ok
  end

  defp fire_after(mod, event, model) when event in @lifecycle_events do
    unless without_events?() do
      run_observers(mod, event, model)
      Laravex.Events.Dispatcher.dispatch(event, %{model: model, module: mod})
    end

    model
  end

  defp run_observers(mod, event, model) do
    Enum.each(observers_for(mod), fn observer ->
      if Code.ensure_loaded?(observer) and function_exported?(observer, event, 1) do
        apply(observer, event, [model])
      end
    end)
  end

  defp observers_for(mod) do
    cond do
      function_exported?(mod, :__observers__, 0) -> List.wrap(mod.__observers__())
      function_exported?(mod, :observes, 0) -> List.wrap(mod.observes())
      true -> []
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

    pager = %{
      data: data,
      total: total,
      per_page: per_page,
      current_page: page,
      last_page: max(1, ceil(total / max(per_page, 1))),
      path: path,
      query: query,
      simple: false
    }

    Map.put(pager, :links, Laravex.Http.Paginator.links(pager, path))
  end

  def cursor_paginate(mod, per_page, opts \\ []) when is_integer(per_page) and per_page > 0 do
    q = mod.query(opts)
    page = Laravex.Database.Query.cursor_paginate(q, per_page, opts)

    %{
      page
      | data: Enum.map(page.data, &mod.from_row/1)
    }
  end

  def simple_paginate(mod, per_page, page, opts \\ []) when page >= 1 do
    offset = (page - 1) * per_page

    rows =
      mod.query()
      |> Laravex.Database.Query.limit(per_page + 1)
      |> Laravex.Database.Query.offset(offset)
      |> Laravex.Database.Query.get()

    has_more = length(rows) > per_page
    data = rows |> Enum.take(per_page) |> Enum.map(&mod.from_row/1)
    path = Keyword.get(opts, :path, "/")

    query =
      opts
      |> Keyword.get(:query, %{})
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.delete("page")

    pager = %{
      data: data,
      per_page: per_page,
      current_page: page,
      has_more_pages: has_more,
      path: path,
      query: query,
      simple: true,
      # for Paginator.links prev/next without last_page math
      last_page: if(has_more, do: page + 1, else: page)
    }

    Map.put(pager, :links, Laravex.Http.Paginator.simple_links(pager, path))
  end

  @doc """
  Constrain `q` to rows that have a related record matching optional `constraint`.

      User.query() |> User.where_has(\"posts\")
      User.query() |> User.where_has(\"posts\", fn q -> Query.where(q, \"published\", 1) end)
  """
  def where_has(owner_mod, %Laravex.Database.Query{} = q, relation, constraint \\ nil) do
    {sql, bindings} = exists_sql(owner_mod, q.table, relation, constraint)
    Laravex.Database.Query.where_raw(q, "EXISTS (#{sql})", bindings)
  end

  def or_where_has(owner_mod, %Laravex.Database.Query{} = q, relation, constraint \\ nil) do
    {sql, bindings} = exists_sql(owner_mod, q.table, relation, constraint)
    Laravex.Database.Query.or_where_raw(q, "EXISTS (#{sql})", bindings)
  end

  def where_doesnt_have(owner_mod, %Laravex.Database.Query{} = q, relation, constraint \\ nil) do
    {sql, bindings} = exists_sql(owner_mod, q.table, relation, constraint)
    Laravex.Database.Query.where_raw(q, "NOT EXISTS (#{sql})", bindings)
  end

  def or_where_doesnt_have(owner_mod, %Laravex.Database.Query{} = q, relation, constraint \\ nil) do
    {sql, bindings} = exists_sql(owner_mod, q.table, relation, constraint)
    Laravex.Database.Query.or_where_raw(q, "NOT EXISTS (#{sql})", bindings)
  end

  defp exists_sql(owner_mod, owner_table, relation, constraint) do
    rel_def = relation_def(owner_mod, relation)

    case rel_def do
      {:has_many, _n, related, fk} ->
        exists_has(owner_table, related, fk, constraint)

      {:has_one, _n, related, fk} ->
        exists_has(owner_table, related, fk, constraint)

      {:belongs_to, _n, related, fk} ->
        exists_belongs_to(owner_table, related, fk, constraint)

      {:belongs_to_many, _n, related, pivot, fk, rk, _pc, _wt} ->
        exists_belongs_to_many(owner_table, related, pivot, fk, rk, constraint)

      {:belongs_to_many, _n, related, pivot, fk, rk} ->
        exists_belongs_to_many(owner_table, related, pivot, fk, rk, constraint)

      {:morph_many, _n, related, morph_name, morph_type} ->
        exists_morph(owner_table, related, morph_name, morph_type, constraint, owner_mod)

      {:morph_one, _n, related, morph_name, morph_type} ->
        exists_morph(owner_table, related, morph_name, morph_type, constraint, owner_mod)

      {:has_many_through, _n, related, through, fk, sk} ->
        exists_has_many_through(owner_table, related, through, fk, sk, constraint)

      {:has_one_through, _n, related, through, fk, sk} ->
        exists_has_many_through(owner_table, related, through, fk, sk, constraint)

      _ ->
        raise ArgumentError, "Unknown relation #{inspect(relation)} on #{inspect(owner_mod)}"
    end
  end

  defp exists_morph(owner_table, related, morph_name, morph_type, constraint, owner_mod) do
    related_table = related.table_name()
    type_col = "#{morph_name}_type"
    id_col = "#{morph_name}_id"
    type_value = morph_type || Laravex.Eloquex.Relation.morph_type(owner_mod)
    {extra, bindings} = constraint_where(related, constraint)
    base = "#{related_table}.#{id_col} = #{owner_table}.id AND #{related_table}.#{type_col} = ?"
    sql = "SELECT 1 FROM #{related_table} WHERE #{base}#{extra_and(extra)}"
    {sql, [type_value | bindings]}
  end

  defp exists_has_many_through(owner_table, related, through, fk, sk, constraint) do
    related_table = related.table_name()
    through_table = through.table_name()
    {extra, bindings} = constraint_where(related, constraint)

    base =
      "#{through_table}.#{fk} = #{owner_table}.id AND #{related_table}.#{sk} = #{through_table}.id"

    sql =
      "SELECT 1 FROM #{related_table} INNER JOIN #{through_table} ON #{through_table}.id = #{related_table}.#{sk} WHERE #{base}#{extra_and(extra)}"

    {sql, bindings}
  end

  defp exists_has(owner_table, related, fk, constraint) do
    related_table = related.table_name()
    {extra, bindings} = constraint_where(related, constraint)
    base = "#{related_table}.#{fk} = #{owner_table}.id"
    sql = "SELECT 1 FROM #{related_table} WHERE #{base}#{extra_and(extra)}"
    {sql, bindings}
  end

  defp exists_belongs_to(owner_table, related, fk, constraint) do
    related_table = related.table_name()
    {extra, bindings} = constraint_where(related, constraint)
    base = "#{related_table}.id = #{owner_table}.#{fk}"
    sql = "SELECT 1 FROM #{related_table} WHERE #{base}#{extra_and(extra)}"
    {sql, bindings}
  end

  defp exists_belongs_to_many(owner_table, related, pivot, fk, rk, constraint) do
    related_table = related.table_name()
    {extra, bindings} = constraint_where(related, constraint)

    base =
      "#{pivot}.#{fk} = #{owner_table}.id AND #{related_table}.id = #{pivot}.#{rk}"

    sql =
      "SELECT 1 FROM #{pivot} INNER JOIN #{related_table} ON #{related_table}.id = #{pivot}.#{rk} WHERE #{base}#{extra_and(extra)}"

    {sql, bindings}
  end

  defp constraint_where(related, nil) do
    Laravex.Database.Query.to_where_sql(related.query())
  end

  defp constraint_where(related, fun) when is_function(fun, 1) do
    related.query()
    |> fun.()
    |> Laravex.Database.Query.to_where_sql()
  end

  defp extra_and(""), do: ""
  defp extra_and(sql) when is_binary(sql), do: " AND #{sql}"

  def with_relations(models, owner_mod, relations) do
    relations
    |> List.wrap()
    |> normalize_with_specs()
    |> Enum.reduce(models, fn {rel_name, constraint}, acc ->
      batch_load_relation(acc, owner_mod, rel_name, constraint: constraint)
    end)
  end

  defp normalize_with_specs(relations) do
    Enum.map(relations, fn
      {name, fun} when is_function(fun, 1) -> {to_string(name), fun}
      {name, nil} -> {to_string(name), nil}
      name when is_atom(name) or is_binary(name) -> {to_string(name), nil}
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

  @doc "Eager-load only relations that are not already loaded."
  def load_missing(model, owner_mod, relations) when not is_list(model) do
    [loaded] = load_missing([model], owner_mod, relations)
    loaded
  end

  def load_missing(models, owner_mod, relations) when is_list(models) do
    rels =
      relations
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.reject(fn name ->
        Enum.all?(models, &relation_loaded?(&1, name))
      end)

    with_relations(models, owner_mod, rels)
  end

  def load_count(model, owner_mod, relations) when not is_list(model) do
    [loaded] = with_counts([model], owner_mod, relations)
    loaded
  end

  def load_count(models, owner_mod, relations) when is_list(models) do
    with_counts(models, owner_mod, relations)
  end

  @doc "Unload relation(s) previously attached via `with`/`load` (clears Process bag)."
  def without(model, relations) do
    relations
    |> List.wrap()
    |> Enum.each(fn name ->
      name = to_string(name)
      Process.delete(relation_key(model, name))
      Process.delete(relation_key(model, name <> "_count"))
    end)

    model
  end

  def batch_load_relation(models, owner_mod, relation_name, opts \\ [])
  def batch_load_relation([], _owner_mod, _relation_name, _opts), do: []

  def batch_load_relation(models, owner_mod, relation_name, opts) do
    relation_name = to_string(relation_name)
    query_opts = Keyword.take(opts, [:with_trashed, :only_trashed])
    constraint = Keyword.get(opts, :constraint)
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
            |> apply_constraint(related, constraint)
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
            |> apply_constraint(related, constraint)
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
        batch_load_belongs_to(models, relation_name, related, fk, query_opts, nil)

      {:belongs_to, _name, related, fk, default} ->
        batch_load_belongs_to(models, relation_name, related, fk, query_opts, default)

      {:belongs_to_many, _name, related, pivot, fk, rk, pivot_cols, _with_ts} ->
        batch_load_belongs_to_many(models, relation_name, related, pivot, fk, rk, pivot_cols, query_opts)

      {:belongs_to_many, _name, related, pivot, fk, rk} ->
        batch_load_belongs_to_many(models, relation_name, related, pivot, fk, rk, [], query_opts)

      {:morph_many, _name, related, morph_name, morph_type} ->
        batch_load_morph_many(models, owner_mod, relation_name, related, morph_name, morph_type, query_opts, constraint)

      {:morph_one, _name, related, morph_name, morph_type} ->
        models
        |> batch_load_morph_many(
          owner_mod,
          relation_name,
          related,
          morph_name,
          morph_type,
          query_opts,
          constraint
        )
        |> Enum.map(fn model ->
          case get_relation(model, relation_name) do
            [row | _] -> put_loaded(model, relation_name, row)
            _ -> put_loaded(model, relation_name, nil)
          end
        end)

      {:morph_to, _name, morph_name, _} ->
        batch_load_morph_to(models, relation_name, morph_name, query_opts)

      {:morph_to_many, _name, related, pivot, morph_name, rk, morph_type} ->
        batch_load_morph_to_many(
          models,
          owner_mod,
          relation_name,
          related,
          pivot,
          morph_name,
          rk,
          morph_type,
          query_opts
        )

      {:has_many_through, _name, related, through, fk, sk} ->
        batch_load_has_many_through(models, relation_name, related, through, fk, sk, query_opts, constraint)

      {:has_one_through, _name, related, through, fk, sk} ->
        models
        |> batch_load_has_many_through(
          relation_name,
          related,
          through,
          fk,
          sk,
          query_opts,
          constraint
        )
        |> Enum.map(fn model ->
          case get_relation(model, relation_name) do
            [row | _] -> put_loaded(model, relation_name, row)
            rows when is_list(rows) -> put_loaded(model, relation_name, List.first(rows))
            row -> put_loaded(model, relation_name, row)
          end
        end)

      _ ->
        models
    end
  end

  defp apply_constraint(q, _related, nil), do: q
  defp apply_constraint(q, _related, fun) when is_function(fun, 1), do: fun.(q)

  defp batch_load_belongs_to(models, relation_name, related, fk, query_opts, default) do
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

    default_value =
      cond do
        is_function(default, 0) -> default.()
        match?(%_{}, default) -> default
        true -> default
      end

    Enum.map(models, fn model ->
      parent_id = Map.get(model, fk_atom)

      value =
        if parent_id do
          Map.get(by_id, parent_id) || default_value
        else
          default_value
        end

      put_loaded(model, relation_name, value)
    end)
  end

  defp batch_load_belongs_to_many(models, relation_name, related, pivot, fk, rk, pivot_cols, query_opts) do
    pivot_cols = Enum.map(List.wrap(pivot_cols), &to_string/1)
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

        if owner_id && child do
          if pivot_cols != [] do
            pivot_data =
              pivot_cols
              |> Enum.map(fn col -> {col, Map.get(row, col) || Map.get(row, String.to_atom(col))} end)
              |> Map.new()

            Process.put(relation_key_by_owner(owner_id, relation_name, related_id), pivot_data)
          end

          Map.update(acc, owner_id, [child], &(&1 ++ [child]))
        else
          acc
        end
      end)

    Enum.map(models, fn model ->
      put_loaded(model, relation_name, Map.get(grouped, model.id, []))
    end)
  end

  defp relation_key_by_owner(owner_id, relation_name, related_id) do
    {:laravex_pivot, owner_id, to_string(relation_name), related_id}
  end

  defp batch_load_morph_many(models, owner_mod, relation_name, related, morph_name, morph_type, query_opts, constraint) do
    type_col = "#{morph_name}_type"
    id_col = "#{morph_name}_id"
    ids = Enum.map(models, & &1.id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    grouped =
      if ids == [] do
        %{}
      else
        related.query(query_opts)
        |> Laravex.Database.Query.where_in(id_col, ids)
        |> apply_constraint(related, constraint)
        |> Laravex.Database.Query.get()
        |> Enum.map(&related.from_row/1)
        |> Enum.filter(fn row ->
          stored_type = Map.get(row, String.to_atom(type_col))

          if morph_type do
            to_string(stored_type) == to_string(morph_type)
          else
            true
          end
        end)
        |> Enum.group_by(fn row ->
          Map.get(row, String.to_atom(id_col))
        end)
      end

    Enum.map(models, fn model ->
      type_value = morph_type || Laravex.Eloquex.Relation.morph_type(owner_mod)

      children =
        Map.get(grouped, model.id, [])
        |> Enum.filter(fn row ->
          stored = Map.get(row, String.to_atom(type_col))
          to_string(stored) == to_string(type_value)
        end)

      put_loaded(model, relation_name, children)
    end)
  end

  defp batch_load_morph_to(models, relation_name, morph_name, query_opts) do
    type_col = String.to_atom("#{morph_name}_type")
    id_col = String.to_atom("#{morph_name}_id")

    targets =
      models
      |> Enum.map(fn model ->
        type = Map.get(model, type_col)
        id = Map.get(model, id_col)
        if type && id, do: {model.id, to_string(type), id}, else: nil
      end)
      |> Enum.reject(&is_nil/1)

    by_type =
      Enum.group_by(targets, fn {_mid, type, _id} -> type end, fn {_mid, _type, id} -> id end)

    loaded =
      Enum.reduce(by_type, %{}, fn {type, type_ids}, acc ->
        case Laravex.Eloquex.Relation.resolve_morph_model(type) do
          mod when is_atom(mod) ->
            ids = Enum.uniq(type_ids)

            rows =
              mod.query(query_opts)
              |> Laravex.Database.Query.where_in("id", ids)
              |> Laravex.Database.Query.get()
              |> Enum.map(&mod.from_row/1)
              |> Map.new(fn row -> {row.id, row} end)

            Map.merge(acc, rows)

          _ ->
            acc
        end
      end)

    Enum.map(models, fn model ->
      type = Map.get(model, type_col)
      id = Map.get(model, id_col)
      value = if type && id, do: Map.get(loaded, id), else: nil
      put_loaded(model, relation_name, value)
    end)
  end

  defp batch_load_morph_to_many(models, owner_mod, relation_name, related, pivot, morph_name, rk, morph_type, query_opts) do
    type_col = "#{morph_name}_type"
    id_col = "#{morph_name}_id"
    ids = Enum.map(models, & &1.id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    morph = morph_type || Laravex.Eloquex.Relation.morph_type(owner_mod)

    pivot_rows =
      if ids == [] do
        []
      else
        Laravex.Database.Query.table(pivot)
        |> Laravex.Database.Query.where(type_col, morph)
        |> Laravex.Database.Query.where_in(id_col, ids)
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
        owner_id = Map.get(row, id_col) || Map.get(row, String.to_atom(id_col))
        related_id = Map.get(row, rk) || Map.get(row, String.to_atom(rk))
        child = Map.get(by_related, related_id)
        if owner_id && child, do: Map.update(acc, owner_id, [child], &(&1 ++ [child])), else: acc
      end)

    Enum.map(models, fn model ->
      put_loaded(model, relation_name, Map.get(grouped, model.id, []))
    end)
  end

  defp batch_load_has_many_through(models, relation_name, related, through, fk, sk, query_opts, constraint) do
    ids = Enum.map(models, & &1.id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    through_rows =
      if ids == [] do
        []
      else
        through.query()
        |> Laravex.Database.Query.where_in(fk, ids)
        |> Laravex.Database.Query.get()
      end

    through_by_owner =
      Enum.reduce(through_rows, %{}, fn row, acc ->
        owner_id = Map.get(row, fk) || Map.get(row, String.to_atom(fk))
        Map.update(acc, owner_id, [row], &(&1 ++ [row]))
      end)

    through_ids =
      through_rows
      |> Enum.map(fn row -> Map.get(row, "id") || Map.get(row, :id) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    related_rows =
      if through_ids == [] do
        []
      else
        related.query(query_opts)
        |> Laravex.Database.Query.where_in(sk, through_ids)
        |> apply_constraint(related, constraint)
        |> Laravex.Database.Query.get()
        |> Enum.map(&related.from_row/1)
      end

    related_by_through =
      Enum.reduce(related_rows, %{}, fn row, acc ->
        through_id = Map.get(row, String.to_atom(sk))
        Map.update(acc, through_id, [row], &(&1 ++ [row]))
      end)

    Enum.map(models, fn model ->
      children =
        (Map.get(through_by_owner, model.id, [])
         |> Enum.flat_map(fn through_row ->
           through_id = Map.get(through_row, "id") || Map.get(through_row, :id)
           Map.get(related_by_through, through_id, [])
         end))

      put_loaded(model, relation_name, children)
    end)
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

        {:belongs_to_many, _n, _related, pivot, fk, _rk, _, _} when ids != [] ->
          pivot_count(pivot, fk, ids)

        {:belongs_to_many, _n, _related, pivot, fk, _rk} when ids != [] ->
          pivot_count(pivot, fk, ids)

        {:morph_many, _n, related, morph_name, morph_type} when ids != [] ->
          type_col = "#{morph_name}_type"
          id_col = "#{morph_name}_id"

          related.query()
          |> Laravex.Database.Query.where_in(id_col, ids)
          |> Laravex.Database.Query.get()
          |> Enum.reduce(%{}, fn row, acc ->
            if morph_type && Map.get(row, type_col) != morph_type do
              acc
            else
              owner_id = Map.get(row, id_col) || Map.get(row, String.to_atom(id_col))
              Map.update(acc, owner_id, 1, &(&1 + 1))
            end
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

  def sync_was_changed(model, changes) when is_map(changes) do
    Process.put(was_changed_key(model), changes)
    model
  end

  def is_dirty?(model, nil) do
    map_size(get_changes(model)) > 0
  end

  def is_dirty?(model, attr) do
    Map.has_key?(get_changes(model), String.to_atom(to_string(attr)))
  end

  def is_clean?(model, attr \\ nil), do: not is_dirty?(model, attr)

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

  def get_original(model, attr \\ nil)

  def get_original(model, nil) do
    Process.get(original_key(model), %{})
  end

  def get_original(model, attr) do
    key = String.to_atom(to_string(attr))
    Map.get(get_original(model, nil), key)
  end

  def was_changed?(model, attr \\ nil)

  def was_changed?(model, nil) do
    map_size(Process.get(was_changed_key(model), %{})) > 0
  end

  def was_changed?(model, attr) do
    Map.has_key?(Process.get(was_changed_key(model), %{}), String.to_atom(to_string(attr)))
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

      relation_defined?(mod, key) ->
        if prevent_lazy_loading?() do
          raise Laravex.Database.LazyLoadingViolationException, model: model, relation: key
        else
          nil
        end

      true ->
        nil
    end
  end

  defp relation_defined?(mod, key) do
    key = to_string(key)

    if function_exported?(mod, :relations, 0) do
      mod.relations()
      |> Enum.any?(fn
        tup when is_tuple(tup) and tuple_size(tup) >= 2 -> to_string(elem(tup, 1)) == key
        _ -> false
      end)
    else
      false
    end
  end

  def apply_persist_casts(attrs, mod) when is_map(attrs) do
    casts = if function_exported?(mod, :casts, 0), do: stringify(mod.casts()), else: %{}

    Map.new(attrs, fn {k, v} ->
      key = to_string(k)
      {key, cast_one(Map.get(casts, key), v)}
    end)
  end

  def refresh(%{__struct__: mod, id: id} = model) when not is_nil(id) do
    opts = if function_exported?(mod, :soft_deletes?, 0) and mod.soft_deletes?(), do: [with_trashed: true], else: []
    mod.find(id, opts) || model
  end

  def refresh(model), do: model

  @doc "Re-fetch a new instance from the DB (Laravel `fresh`). Returns nil if missing."
  def fresh(model, relations \\ [])

  def fresh(%{__struct__: mod, id: id} = _model, relations) when not is_nil(id) do
    opts =
      if function_exported?(mod, :soft_deletes?, 0) and mod.soft_deletes?(),
        do: [with_trashed: true],
        else: []

    case mod.find(id, opts) do
      nil ->
        nil

      found ->
        relations = List.wrap(relations)

        if relations == [] do
          found
        else
          [loaded] = with_relations([found], mod, relations)
          loaded
        end
    end
  end

  def fresh(model, _relations), do: model

  @doc "Clone the model without persisting; drops id/timestamps by default (Laravel `replicate`)."
  def replicate(model, except \\ [])

  def replicate(%{__struct__: mod} = model, except) do
    except =
      (["id", "created_at", "updated_at", "deleted_at"] ++ List.wrap(except))
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    attrs =
      model
      |> Map.from_struct()
      |> Enum.reject(fn {k, _} ->
        k in [:__struct__, :__relations__] or MapSet.member?(except, to_string(k))
      end)
      |> Map.new(fn {k, v} -> {to_string(k), v} end)

    mod.new(attrs)
  end

  def increment(%{__struct__: mod, id: id} = model, column, amount \\ 1)
      when not is_nil(id) and is_integer(amount) do
    col = to_string(column)
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    Laravex.Database.Connection.execute(
      "UPDATE #{mod.table_name()} SET #{col} = COALESCE(#{col}, 0) + ?, updated_at = ? WHERE id = ?",
      [amount, now, id]
    )

    refresh(model)
  end

  def decrement(model, column, amount \\ 1), do: increment(model, column, -amount)

  def touch(model, attr \\ "updated_at")

  def touch(%{id: nil} = model, _attr), do: model

  def touch(%{__struct__: mod, id: id} = model, attr) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    attr = to_string(attr)

    Laravex.Database.Query.table(mod.table_name())
    |> Laravex.Database.Query.where("id", id)
    |> Laravex.Database.Query.update(%{attr => now, "updated_at" => now})

    touched = Map.put(model, String.to_atom(attr), now) |> Map.put(:updated_at, now)
    _ = sync_original(touched)
    _ = touch_parents(touched)
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

  def make_hidden(model, attrs) do
    attrs = List.wrap(attrs) |> Enum.map(&to_string/1)
    key = serialization_key(model)
    %{hidden: hidden, visible: visible} = Process.get(key, %{hidden: [], visible: []})
    _ = Process.put(key, %{hidden: hidden ++ attrs, visible: visible})
    model
  end

  def make_visible(model, attrs) do
    attrs = List.wrap(attrs) |> Enum.map(&to_string/1)
    key = serialization_key(model)
    %{hidden: hidden, visible: visible} = Process.get(key, %{hidden: [], visible: []})
    _ = Process.put(key, %{hidden: hidden, visible: visible ++ attrs})
    model
  end

  def to_map(model) do
    mod = model.__struct__
    base_hidden = if function_exported?(mod, :hidden, 0), do: Enum.map(mod.hidden(), &to_string/1), else: []
    %{hidden: extra_hidden, visible: extra_visible} =
      Process.get(serialization_key(model), %{hidden: [], visible: []})

    hidden =
      (base_hidden ++ extra_hidden)
      |> Enum.uniq()
      |> Enum.reject(&(&1 in extra_visible))

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

  defp serialization_key(model), do: {:laravex_serialization, model.__struct__, Map.get(model, :id)}

  defp was_changed_key(model), do: {:laravex_was_changed, model.__struct__, Map.get(model, :id)}

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

  defp pivot_count(pivot, fk, ids) do
    Laravex.Database.Query.table(pivot)
    |> Laravex.Database.Query.where_in(fk, ids)
    |> Laravex.Database.Query.get()
    |> Enum.reduce(%{}, fn row, acc ->
      owner_id = Map.get(row, fk) || Map.get(row, String.to_atom(fk))
      Map.update(acc, owner_id, 1, &(&1 + 1))
    end)
  end
end

defmodule Laravex.Database.LazyLoadingViolationException do
  @moduledoc "Raised when lazy loading is prevented and a relation is accessed without eager loading."
  defexception [:message, :model, :relation]

  @impl true
  def exception(opts) do
    relation = Keyword.fetch!(opts, :relation)
    model = Keyword.get(opts, :model)

    %__MODULE__{
      message: "lazy loading relation #{inspect(relation)} on #{inspect(model)} is not allowed",
      model: model,
      relation: relation
    }
  end
end
