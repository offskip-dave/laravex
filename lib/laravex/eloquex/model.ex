defmodule Laravex.Eloquex.Model do
  @moduledoc """
  Eloquex model base. Extends `Laravex.Database.Model` with scopes macros,
  `first_or_create` / `update_or_create`, and relation accessors.
  """

  defmacro __using__(opts) do
    quote do
      use Laravex.Database.Model, unquote(opts)
      import Laravex.Eloquex.Model, only: [scope: 2, global_scope: 2]

      Module.register_attribute(__MODULE__, :eloquex_global_scopes, accumulate: true)

      @before_compile Laravex.Eloquex.Model

      def first_or_create(attrs, values \\ %{}) do
        Laravex.Eloquex.Model.first_or_create(__MODULE__, attrs, values)
      end

      def first_or_new(attrs, values \\ %{}) do
        Laravex.Eloquex.Model.first_or_new(__MODULE__, attrs, values)
      end

      def update_or_create(attrs, values \\ %{}) do
        Laravex.Eloquex.Model.update_or_create(__MODULE__, attrs, values)
      end

      def association(%__MODULE__{} = model, name) do
        Laravex.Eloquex.Relation.for(model, name)
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __global_scopes__, do: @eloquex_global_scopes
    end
  end

  @doc """
  Define a local scope.

      scope :active do
        Laravex.Database.Query.where(query, "active", 1)
      end
  """
  defmacro scope(name, do: body) do
    fun = :"scope_#{name}"

    quote do
      def unquote(fun)(var!(query)) do
        unquote(body)
      end
    end
  end

  @doc """
  Register a global scope applied on every `query/1` unless
  `without_global_scopes: true`.
  """
  defmacro global_scope(name, do: body) do
    quote do
      @eloquex_global_scopes {unquote(name),
                              fn var!(query) ->
                                unquote(body)
                              end}
    end
  end

  def first_or_create(mod, attrs, values \\ %{}) do
    attrs = Laravex.Database.Model.stringify(attrs)
    values = Laravex.Database.Model.stringify(values)

    q =
      Enum.reduce(attrs, mod.query(), fn {k, v}, acc ->
        Laravex.Database.Query.where(acc, k, v)
      end)

    case Laravex.Database.Query.first(q) do
      nil -> mod.create(Map.merge(attrs, values))
      row -> mod.from_row(row)
    end
  end

  @doc "Find by attributes or instantiate without saving (Laravel `firstOrNew`)."
  def first_or_new(mod, attrs, values \\ %{}) do
    attrs = Laravex.Database.Model.stringify(attrs)
    values = Laravex.Database.Model.stringify(values)

    q =
      Enum.reduce(attrs, mod.query(), fn {k, v}, acc ->
        Laravex.Database.Query.where(acc, k, v)
      end)

    case Laravex.Database.Query.first(q) do
      nil -> mod.new(Map.merge(attrs, values))
      row -> mod.from_row(row)
    end
  end

  def update_or_create(mod, attrs, values \\ %{}) do
    attrs = Laravex.Database.Model.stringify(attrs)
    values = Laravex.Database.Model.stringify(values)

    q =
      Enum.reduce(attrs, mod.query(), fn {k, v}, acc ->
        Laravex.Database.Query.where(acc, k, v)
      end)

    case Laravex.Database.Query.first(q) do
      nil ->
        mod.create(Map.merge(attrs, values))

      row ->
        model = mod.from_row(row)

        Enum.reduce(values, model, fn {k, v}, acc ->
          Map.put(acc, String.to_atom(k), v)
        end)
        |> mod.save()
    end
  end
end
