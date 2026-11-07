defmodule Laravex.Eloquex.Relation do
  @moduledoc "Eloquex HasMany / BelongsTo relation helpers."

  defmodule HasMany do
    defstruct [:owner, :related, :foreign_key, :name]

    def get(%__MODULE__{owner: owner, related: related, foreign_key: fk}) do
      related.where(fk, owner.id)
    end

    def create(%__MODULE__{owner: owner, related: related, foreign_key: fk}, attrs)
        when is_map(attrs) do
      attrs =
        attrs
        |> Laravex.Database.Model.stringify()
        |> Map.put(fk, owner.id)

      related.create(attrs)
    end

    def count(%__MODULE__{} = rel), do: length(get(rel))
  end

  defmodule BelongsTo do
    defstruct [:owner, :related, :foreign_key, :name]

    def get(%__MODULE__{owner: owner, related: related, foreign_key: fk}) do
      fk_atom = String.to_atom(fk)
      id = Map.get(owner, fk_atom)
      if id, do: related.find(id), else: nil
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
