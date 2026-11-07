defmodule Laravex.Eloquex.Relation do
  @moduledoc """
  Eloquex relation helpers: HasMany, HasOne, BelongsTo, BelongsToMany.

  Related queries honor soft deletes via `related.query/1` (pass `with_trashed: true`
  to include trashed children). BelongsToMany supports lite `attach` / `detach` / `sync`.
  """

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
    defstruct [:owner, :related, :foreign_key, :name]

    def get(%__MODULE__{owner: owner, related: related, foreign_key: fk}, opts \\ []) do
      fk_atom = String.to_atom(fk)
      id = Map.get(owner, fk_atom)

      if id do
        related.find(id, opts)
      else
        nil
      end
    end

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
    defstruct [:owner, :related, :pivot, :foreign_key, :related_key, :name]

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

      Enum.each(List.wrap(ids), fn id ->
        row =
          attrs
          |> Map.put(rel.foreign_key, rel.owner.id)
          |> Map.put(rel.related_key, id)
          |> Map.put_new("created_at", now)
          |> Map.put_new("updated_at", now)

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
      now = DateTime.utc_now() |> DateTime.to_iso8601()
      attrs = Map.put_new(attrs, "updated_at", now)

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
        %BelongsTo{owner: model, related: related, foreign_key: fk, name: n}

      {:belongs_to_many, n, related, pivot, fk, rk} ->
        %BelongsToMany{
          owner: model,
          related: related,
          pivot: pivot,
          foreign_key: fk,
          related_key: rk,
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
