defmodule Laravex.Eloquex.Relation do
  @moduledoc """
  Eloquex HasMany / BelongsTo relation helpers.

  Related queries honor soft deletes via `related.query/1` (pass `with_trashed: true`
  to include trashed children).
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

  def for(model, name) when is_atom(name) or is_binary(name) do
    owner_mod = model.__struct__
    name_str = to_string(name)

    relations =
      if function_exported?(owner_mod, :relations, 0), do: owner_mod.relations(), else: []

    case Enum.find(relations, fn
           {_, n, _, _} -> to_string(n) == name_str
           _ -> false
         end) do
      {:has_many, n, related, fk} ->
        %HasMany{owner: model, related: related, foreign_key: fk, name: n}

      {:belongs_to, n, related, fk} ->
        %BelongsTo{owner: model, related: related, foreign_key: fk, name: n}

      _ ->
        nil
    end
  end
end
