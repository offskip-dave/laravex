defmodule Laravex.Eloquex.Relation do
  @moduledoc """
  Eloquex relation helpers: HasMany, HasOne, BelongsTo, BelongsToMany,
  polymorphic (morph_*) and through relations.

  Related queries honor soft deletes via `related.query/1` (pass `with_trashed: true`
  to include trashed children). BelongsToMany supports lite `attach` / `detach` / `sync`.
  """

  @doc "Stored morph `*_type` value for a model (table name or underscored module segment)."
  def morph_type(module) when is_atom(module) do
    cond do
      function_exported?(module, :morph_class, 0) ->
        module.morph_class()

      function_exported?(module, :table_name, 0) ->
        module.table_name()

      true ->
        module |> Module.split() |> List.last() |> Macro.underscore()
    end
  end

  @doc "Resolve a morph `*_type` string to a model module."
  def resolve_morph_model(type) when is_binary(type) do
    cond do
      Map.has_key?(morph_map(), type) ->
        morph_map()[type]

      String.contains?(type, ".") ->
        safe_concat_module(type)

      true ->
        case morph_map()[type] do
          nil ->
            mod = Module.concat(["App", "Models", Macro.camelize(Macro.underscore(type))])

            if Code.ensure_loaded?(mod) do
              mod
            else
              safe_concat_module("App.Models.#{Macro.camelize(type)}")
            end

          mod ->
            mod
        end
    end
  end

  def resolve_morph_model(_), do: nil

  defp morph_map do
    case Laravex.Config.Repository.get("database.morph_map") do
      map when is_map(map) -> normalize_morph_map(map)
      _ -> normalize_morph_map(Application.get_env(:laravex, :morph_map, %{}))
    end
  end

  defp normalize_morph_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp safe_concat_module(string) do
    mod =
      string
      |> String.split(".")
      |> Module.concat()

    if Code.ensure_loaded?(mod), do: mod, else: nil
  rescue
    ArgumentError -> nil
  end

  defmodule HasMany do
    defstruct [:owner, :related, :foreign_key, :name]

    def get(%__MODULE__{owner: owner, related: related, foreign_key: fk}, opts \\ []) do
      related.query(opts)
      |> Laravex.Database.Query.where(fk, owner.id)
      |> Laravex.Database.Query.get()
      |> Enum.map(&related.from_row/1)
    end

    def create(%__MODULE__{owner: owner, related: related, foreign_key: fk}, attrs)
        when is_map(attrs) do
      attrs =
        attrs
        |> Laravex.Database.Model.stringify()
        |> Map.put(fk, owner.id)

      related.create(attrs)
    end

    def count(%__MODULE__{} = rel, opts \\ []), do: length(get(rel, opts))
  end

  defmodule HasOne do
    defstruct [:owner, :related, :foreign_key, :name]

    def get(%__MODULE__{} = rel, opts \\ []) do
      case HasMany.get(
             %HasMany{
               owner: rel.owner,
               related: rel.related,
               foreign_key: rel.foreign_key,
               name: rel.name
             },
             opts
           ) do
        [row | _] -> row
        _ -> nil
      end
    end

    def create(%__MODULE__{} = rel, attrs) when is_map(attrs) do
      HasMany.create(
        %HasMany{
          owner: rel.owner,
          related: rel.related,
          foreign_key: rel.foreign_key,
          name: rel.name
        },
        attrs
      )
    end
  end

  defmodule BelongsTo do
    defstruct [:owner, :related, :foreign_key, :name, :default]

    def get(%__MODULE__{owner: owner, related: related, foreign_key: fk, default: default}, opts \\ []) do
      fk_atom = String.to_atom(fk)
      id = Map.get(owner, fk_atom)

      result =
        if id do
          related.find(id, opts)
        else
          nil
        end

      result || default_value(default)
    end

    defp default_value(nil), do: nil
    defp default_value(fun) when is_function(fun, 0), do: fun.()
    defp default_value(%_{} = struct), do: struct
    defp default_value(other), do: other

    def associate(%__MODULE__{owner: owner, foreign_key: fk}, parent) do
      fk_atom = String.to_atom(fk)
      Map.put(owner, fk_atom, Map.get(parent, :id))
    end

    def dissociate(%__MODULE__{owner: owner, foreign_key: fk}) do
      fk_atom = String.to_atom(fk)
      Map.put(owner, fk_atom, nil)
    end
  end

  defmodule BelongsToMany do
    defstruct [
      :owner,
      :related,
      :pivot,
      :foreign_key,
      :related_key,
      :name,
      :pivot_columns,
      :with_timestamps
    ]

    def get(%__MODULE__{} = rel, opts \\ []) do
      ids = related_ids(rel)

      if ids == [] do
        []
      else
        related = rel.related

        related.query(opts)
        |> Laravex.Database.Query.where_in("id", ids)
        |> Laravex.Database.Query.get()
        |> Enum.map(&related.from_row/1)
      end
    end

    def related_ids(%__MODULE__{owner: owner, pivot: pivot, foreign_key: fk, related_key: rk}) do
      Laravex.Database.Query.table(pivot)
      |> Laravex.Database.Query.where(fk, owner.id)
      |> Laravex.Database.Query.get()
      |> Enum.map(fn row -> Map.get(row, rk) || Map.get(row, String.to_atom(rk)) end)
      |> Enum.reject(&is_nil/1)
    end

    def attach(%__MODULE__{} = rel, ids, attrs \\ %{}) do
      attrs = Laravex.Database.Model.stringify(attrs)
      now = DateTime.utc_now() |> DateTime.to_iso8601()
      with_ts? = rel.with_timestamps != false

      Enum.each(List.wrap(ids), fn id ->
        row =
          attrs
          |> Map.put(rel.foreign_key, rel.owner.id)
          |> Map.put(rel.related_key, id)

        row =
          if with_ts? do
            row
            |> Map.put_new("created_at", now)
            |> Map.put_new("updated_at", now)
          else
            row
          end

        insert_pivot(rel.pivot, row)
      end)

      :ok
    end

    def detach(%__MODULE__{} = rel, ids \\ :all) do
      q =
        Laravex.Database.Query.table(rel.pivot)
        |> Laravex.Database.Query.where(rel.foreign_key, rel.owner.id)

      q =
        case ids do
          :all -> q
          list -> Laravex.Database.Query.where_in(q, rel.related_key, List.wrap(list))
        end

      Laravex.Database.Query.delete(q)
      :ok
    end

    def sync(%__MODULE__{} = rel, ids) do
      detach(rel, :all)
      attach(rel, ids)
    end

    @doc "Attach missing ids without detaching existing ones (Laravel `syncWithoutDetaching`)."
    def sync_without_detaching(%__MODULE__{} = rel, ids) do
      current = MapSet.new(related_ids(rel), &to_string/1)

      List.wrap(ids)
      |> Enum.reject(fn id -> MapSet.member?(current, to_string(id)) end)
      |> then(&attach(rel, &1))
    end

    @doc "Toggle attachment of the given ids (Laravel `toggle`)."
    def toggle(%__MODULE__{} = rel, ids) do
      current = MapSet.new(related_ids(rel), &to_string/1)

      {attach_ids, detach_ids} =
        List.wrap(ids)
        |> Enum.split_with(fn id -> not MapSet.member?(current, to_string(id)) end)

      if detach_ids != [], do: detach(rel, detach_ids)
      if attach_ids != [], do: attach(rel, attach_ids)
      :ok
    end

    @doc "Update pivot attributes for a related id (Laravel `updateExistingPivot`)."
    def update_existing_pivot(%__MODULE__{} = rel, id, attrs) when is_map(attrs) do
      attrs = Laravex.Database.Model.stringify(attrs)

      attrs =
        if rel.with_timestamps != false do
          now = DateTime.utc_now() |> DateTime.to_iso8601()
          Map.put_new(attrs, "updated_at", now)
        else
          attrs
        end

      sets =
        attrs
        |> Enum.map(fn {k, _} -> "#{k} = ?" end)
        |> Enum.join(", ")

      vals = Enum.map(attrs, fn {_, v} -> v end) ++ [rel.owner.id, id]

      Laravex.Database.Connection.execute(
        "UPDATE #{rel.pivot} SET #{sets} WHERE #{rel.foreign_key} = ? AND #{rel.related_key} = ?",
        vals
      )

      :ok
    end

    def count(%__MODULE__{} = rel), do: length(related_ids(rel))

    defp insert_pivot(pivot, attrs) when is_map(attrs) do
      cols = Map.keys(attrs) |> Enum.map(&to_string/1)
      vals = Enum.map(cols, &Map.get(attrs, &1))
      placeholders = Enum.map_join(cols, ", ", fn _ -> "?" end)

      Laravex.Database.Connection.execute(
        "INSERT INTO #{pivot} (#{Enum.join(cols, ", ")}) VALUES (#{placeholders})",
        vals
      )
    end
  end

  defmodule MorphMany do
    defstruct [:owner, :related, :morph_name, :morph_type, :name]

    def get(%__MODULE__{} = rel, opts \\ []) do
      type_col = "#{rel.morph_name}_type"
      id_col = "#{rel.morph_name}_id"
      morph_type = rel.morph_type || Laravex.Eloquex.Relation.morph_type(rel.owner.__struct__)

      related = rel.related

      related.query(opts)
      |> Laravex.Database.Query.where(type_col, morph_type)
      |> Laravex.Database.Query.where(id_col, rel.owner.id)
      |> Laravex.Database.Query.get()
      |> Enum.map(&related.from_row/1)
    end

    def create(%__MODULE__{} = rel, attrs) when is_map(attrs) do
      type_col = "#{rel.morph_name}_type"
      id_col = "#{rel.morph_name}_id"
      morph_type = rel.morph_type || Laravex.Eloquex.Relation.morph_type(rel.owner.__struct__)

      attrs =
        attrs
        |> Laravex.Database.Model.stringify()
        |> Map.put(type_col, morph_type)
        |> Map.put(id_col, rel.owner.id)

      rel.related.create(attrs)
    end
  end

  defmodule MorphOne do
    defstruct [:owner, :related, :morph_name, :morph_type, :name]

    def get(%__MODULE__{} = rel, opts \\ []) do
      case MorphMany.get(
             %MorphMany{
               owner: rel.owner,
               related: rel.related,
               morph_name: rel.morph_name,
               morph_type: rel.morph_type,
               name: rel.name
             },
             opts
           ) do
        [row | _] -> row
        _ -> nil
      end
    end

    def create(%__MODULE__{} = rel, attrs) when is_map(attrs) do
      MorphMany.create(
        %MorphMany{
          owner: rel.owner,
          related: rel.related,
          morph_name: rel.morph_name,
          morph_type: rel.morph_type,
          name: rel.name
        },
        attrs
      )
    end
  end

  defmodule MorphTo do
    defstruct [:owner, :morph_name, :name]

    def get(%__MODULE__{owner: owner, morph_name: morph_name}, opts \\ []) do
      type_col = String.to_atom("#{morph_name}_type")
      id_col = String.to_atom("#{morph_name}_id")
      type = Map.get(owner, type_col)
      id = Map.get(owner, id_col)

      if type && id do
        case Laravex.Eloquex.Relation.resolve_morph_model(to_string(type)) do
          mod when is_atom(mod) -> mod.find(id, opts)
          _ -> nil
        end
      else
        nil
      end
    end

    def associate(%__MODULE__{} = rel, parent) do
      type_col = String.to_atom("#{rel.morph_name}_type")
      id_col = String.to_atom("#{rel.morph_name}_id")
      morph_type = Laravex.Eloquex.Relation.morph_type(parent.__struct__)

      rel.owner
      |> Map.put(type_col, morph_type)
      |> Map.put(id_col, Map.get(parent, :id))
    end

    def dissociate(%__MODULE__{owner: owner, morph_name: morph_name}) do
      type_col = String.to_atom("#{morph_name}_type")
      id_col = String.to_atom("#{morph_name}_id")

      owner
      |> Map.put(type_col, nil)
      |> Map.put(id_col, nil)
    end
  end

  defmodule MorphToMany do
    defstruct [:owner, :related, :pivot, :morph_name, :morph_type, :related_key, :name]

    def get(%__MODULE__{} = rel, opts \\ []) do
      type_col = "#{rel.morph_name}_type"
      id_col = "#{rel.morph_name}_id"
      morph_type = rel.morph_type || Laravex.Eloquex.Relation.morph_type(rel.owner.__struct__)

      pivot_rows =
        Laravex.Database.Query.table(rel.pivot)
        |> Laravex.Database.Query.where(type_col, morph_type)
        |> Laravex.Database.Query.where(id_col, rel.owner.id)
        |> Laravex.Database.Query.get()

      ids =
        pivot_rows
        |> Enum.map(fn row -> Map.get(row, rel.related_key) || Map.get(row, String.to_atom(rel.related_key)) end)
        |> Enum.reject(&is_nil/1)

      if ids == [] do
        []
      else
        related = rel.related

        related.query(opts)
        |> Laravex.Database.Query.where_in("id", ids)
        |> Laravex.Database.Query.get()
        |> Enum.map(&related.from_row/1)
      end
    end

    def attach(%__MODULE__{} = rel, ids, attrs \\ %{}) do
      type_col = "#{rel.morph_name}_type"
      id_col = "#{rel.morph_name}_id"
      morph_type = rel.morph_type || Laravex.Eloquex.Relation.morph_type(rel.owner.__struct__)
      attrs = Laravex.Database.Model.stringify(attrs)

      Enum.each(List.wrap(ids), fn id ->
        row =
          attrs
          |> Map.put(type_col, morph_type)
          |> Map.put(id_col, rel.owner.id)
          |> Map.put(rel.related_key, id)

        Laravex.Eloquex.Relation.insert_pivot_public(rel.pivot, row)
      end)

      :ok
    end

    def detach(%__MODULE__{} = rel, ids \\ :all) do
      type_col = "#{rel.morph_name}_type"
      id_col = "#{rel.morph_name}_id"
      morph_type = rel.morph_type || Laravex.Eloquex.Relation.morph_type(rel.owner.__struct__)

      q =
        Laravex.Database.Query.table(rel.pivot)
        |> Laravex.Database.Query.where(type_col, morph_type)
        |> Laravex.Database.Query.where(id_col, rel.owner.id)

      q =
        case ids do
          :all -> q
          list -> Laravex.Database.Query.where_in(q, rel.related_key, List.wrap(list))
        end

      Laravex.Database.Query.delete(q)
      :ok
    end

    def sync(%__MODULE__{} = rel, ids) do
      detach(rel, :all)
      attach(rel, ids)
    end
  end

  defmodule HasManyThrough do
    defstruct [:owner, :related, :through, :foreign_key, :second_key, :name]

    def get(%__MODULE__{} = rel, opts \\ []) do
      through_table = rel.through.table_name()
      related_table = rel.related.table_name()
      related = rel.related

      sql = """
      SELECT #{related_table}.* FROM #{related_table}
      INNER JOIN #{through_table} ON #{through_table}.id = #{related_table}.#{rel.second_key}
      WHERE #{through_table}.#{rel.foreign_key} = ?
      """

      Laravex.Database.Connection.query(sql, [rel.owner.id])
      |> Enum.map(&related.from_row/1)
      |> apply_soft_delete_filter(related, opts)
    end

    defp apply_soft_delete_filter(models, mod, opts) do
      if Keyword.get(opts, :with_trashed, false) or not function_exported?(mod, :soft_deletes?, 0) or
           not mod.soft_deletes?() do
        models
      else
        Enum.reject(models, fn m -> mod.trashed?(m) end)
      end
    end
  end

  defmodule HasOneThrough do
    defstruct [:owner, :related, :through, :foreign_key, :second_key, :name]

    def get(%__MODULE__{} = rel, opts \\ []) do
      case HasManyThrough.get(
             %HasManyThrough{
               owner: rel.owner,
               related: rel.related,
               through: rel.through,
               foreign_key: rel.foreign_key,
               second_key: rel.second_key,
               name: rel.name
             },
             opts
           ) do
        [row | _] -> row
        _ -> nil
      end
    end
  end

  def insert_pivot_public(pivot, attrs) when is_map(attrs) do
    cols = Map.keys(attrs) |> Enum.map(&to_string/1)
    vals = Enum.map(cols, &Map.get(attrs, &1))
    placeholders = Enum.map_join(cols, ", ", fn _ -> "?" end)

    Laravex.Database.Connection.execute(
      "INSERT INTO #{pivot} (#{Enum.join(cols, ", ")}) VALUES (#{placeholders})",
      vals
    )
  end

  def for(model, name) when is_atom(name) or is_binary(name) do
    owner_mod = model.__struct__
    name_str = to_string(name)

    relations =
      if function_exported?(owner_mod, :relations, 0), do: owner_mod.relations(), else: []

    case find_def(relations, name_str) do
      {:has_many, n, related, fk} ->
        %HasMany{owner: model, related: related, foreign_key: fk, name: n}

      {:has_one, n, related, fk} ->
        %HasOne{owner: model, related: related, foreign_key: fk, name: n}

      {:belongs_to, n, related, fk} ->
        %BelongsTo{owner: model, related: related, foreign_key: fk, name: n, default: nil}

      {:belongs_to, n, related, fk, default} ->
        %BelongsTo{owner: model, related: related, foreign_key: fk, name: n, default: default}

      {:belongs_to_many, n, related, pivot, fk, rk, pivot_cols, with_ts} ->
        %BelongsToMany{
          owner: model,
          related: related,
          pivot: pivot,
          foreign_key: fk,
          related_key: rk,
          name: n,
          pivot_columns: pivot_cols || [],
          with_timestamps: with_ts
        }

      {:belongs_to_many, n, related, pivot, fk, rk} ->
        %BelongsToMany{
          owner: model,
          related: related,
          pivot: pivot,
          foreign_key: fk,
          related_key: rk,
          name: n,
          pivot_columns: [],
          with_timestamps: true
        }

      {:morph_many, n, related, morph_name, morph_type} ->
        %MorphMany{
          owner: model,
          related: related,
          morph_name: morph_name,
          morph_type: morph_type,
          name: n
        }

      {:morph_one, n, related, morph_name, morph_type} ->
        %MorphOne{
          owner: model,
          related: related,
          morph_name: morph_name,
          morph_type: morph_type,
          name: n
        }

      {:morph_to, n, morph_name, _} ->
        %MorphTo{owner: model, morph_name: morph_name, name: n}

      {:morph_to_many, n, related, pivot, morph_name, rk, morph_type} ->
        %MorphToMany{
          owner: model,
          related: related,
          pivot: pivot,
          morph_name: morph_name,
          morph_type: morph_type,
          related_key: rk,
          name: n
        }

      {:has_many_through, n, related, through, fk, sk} ->
        %HasManyThrough{
          owner: model,
          related: related,
          through: through,
          foreign_key: fk,
          second_key: sk,
          name: n
        }

      {:has_one_through, n, related, through, fk, sk} ->
        %HasOneThrough{
          owner: model,
          related: related,
          through: through,
          foreign_key: fk,
          second_key: sk,
          name: n
        }

      _ ->
        nil
    end
  end

  def find_def(relations, name_str) when is_list(relations) do
    Enum.find(relations, fn
      tup when is_tuple(tup) and tuple_size(tup) >= 2 ->
        to_string(elem(tup, 1)) == to_string(name_str)

      _ ->
        false
    end)
  end
end
