defmodule Laravex.Database.Model do
  @moduledoc """
  Eloquent-shaped ActiveRecord base. Use with `use Laravex.Database.Model, table: "users"`.
  """

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)

    quote do
      def table_name, do: unquote(table)

      def new(attrs \\ %{}) when is_map(attrs) do
        attrs = Laravex.Database.Model.stringify(attrs)
        casted = Laravex.Database.Model.cast_attrs(__MODULE__, attrs)
        struct(__MODULE__, Laravex.Database.Model.atomize(casted))
      end

      def query, do: Laravex.Database.Query.table(table_name())

      def all do
        query() |> Laravex.Database.Query.get() |> Enum.map(&from_row/1)
      end

      def find(id) do
        case query() |> Laravex.Database.Query.where("id", id) |> Laravex.Database.Query.first() do
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

      def create(attrs) when is_map(attrs) do
        model = new(attrs)
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        row =
          model
          |> Map.from_struct()
          |> Map.drop([:__struct__, :id])
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
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

        attrs =
          model
          |> Map.from_struct()
          |> Map.drop([:id])
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new(fn {k, v} -> {to_string(k), v} end)
          |> Map.put("updated_at", now)

        query()
        |> Laravex.Database.Query.where("id", id)
        |> Laravex.Database.Query.update(attrs)

        find(id)
      end

      def delete(%__MODULE__{id: id}) do
        query() |> Laravex.Database.Query.where("id", id) |> Laravex.Database.Query.delete()
        :ok
      end

      def from_row(row) when is_map(row) do
        new(row)
      end

      defoverridable new: 0, new: 1, find_by_email: 1
    end
  end

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
      k in fillable or k in ["id", "created_at", "updated_at", "email_verified_at", "remember_token"]
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
  defp cast_one(_, v), do: v
end
