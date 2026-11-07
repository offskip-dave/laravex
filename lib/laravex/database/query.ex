defmodule Laravex.Database.Query do
  @moduledoc "Fluent query builder."

  defstruct table: nil,
            wheres: [],
            bindings: [],
            order: nil,
            limit: nil,
            offset: nil,
            columns: ["*"]

  def table(name), do: %__MODULE__{table: name}

  def select(%__MODULE__{} = q, cols) when is_list(cols), do: %{q | columns: cols}

  def where(%__MODULE__{} = q, column, value) do
    %{q | wheres: q.wheres ++ [{"#{column} = ?", value}], bindings: q.bindings ++ [value]}
  end

  def where(%__MODULE__{} = q, column, op, value) do
    %{q | wheres: q.wheres ++ [{"#{column} #{op} ?", value}], bindings: q.bindings ++ [value]}
  end

  def where_null(%__MODULE__{} = q, column) do
    %{q | wheres: q.wheres ++ [{"#{column} IS NULL", :skip}]}
  end

  def where_not_null(%__MODULE__{} = q, column) do
    %{q | wheres: q.wheres ++ [{"#{column} IS NOT NULL", :skip}]}
  end

  def where_in(%__MODULE__{} = q, column, values) when is_list(values) do
    if values == [] do
      %{q | wheres: q.wheres ++ [{"1 = 0", :skip}]}
    else
      placeholders = Enum.map_join(values, ", ", fn _ -> "?" end)

      %{
        q
        | wheres: q.wheres ++ [{"#{column} IN (#{placeholders})", :in}],
          bindings: q.bindings ++ values
      }
    end
  end

  def exists?(%__MODULE__{} = q) do
    case q |> limit(1) |> get() do
      [] -> false
      _ -> true
    end
  end

  def order_by(%__MODULE__{} = q, column, dir \\ "asc") do
    %{q | order: "#{column} #{String.upcase(to_string(dir))}"}
  end

  def limit(%__MODULE__{} = q, n), do: %{q | limit: n}
  def offset(%__MODULE__{} = q, n), do: %{q | offset: n}

  def get(%__MODULE__{} = q) do
    Laravex.Database.Connection.query(to_sql(q), q.bindings)
  end

  def first(%__MODULE__{} = q) do
    q |> limit(1) |> get() |> List.first()
  end

  def insert(table, attrs) when is_binary(table) and is_map(attrs) do
    cols = Map.keys(attrs) |> Enum.map(&to_string/1)
    vals = Enum.map(cols, &Map.get(attrs, &1) || Map.get(attrs, String.to_atom(&1)))
    placeholders = Enum.map_join(cols, ", ", fn _ -> "?" end)

    rows =
      Laravex.Database.Connection.query(
        "INSERT INTO #{table} (#{Enum.join(cols, ", ")}) VALUES (#{placeholders}) RETURNING id",
        vals
      )

    case rows do
      [%{"id" => id}] -> id
      _ -> nil
    end
  end

  def update(%__MODULE__{} = q, attrs) when is_map(attrs) do
    sets =
      attrs
      |> Enum.map(fn {k, _} -> "#{k} = ?" end)
      |> Enum.join(", ")

    vals = Enum.map(attrs, fn {_, v} -> v end)
    where_sql = where_clause(q)

    Laravex.Database.Connection.execute(
      "UPDATE #{q.table} SET #{sets}#{where_sql}",
      vals ++ q.bindings
    )
  end

  def delete(%__MODULE__{} = q) do
    Laravex.Database.Connection.execute("DELETE FROM #{q.table}#{where_clause(q)}", q.bindings)
  end

  def count(%__MODULE__{} = q) do
    sql = "SELECT COUNT(*) AS aggregate FROM #{q.table}#{where_clause(q)}"

    case Laravex.Database.Connection.query(sql, q.bindings) do
      [%{"aggregate" => n}] -> n
      _ -> 0
    end
  end

  defp to_sql(%__MODULE__{} = q) do
    cols = Enum.join(q.columns, ", ")

    "SELECT #{cols} FROM #{q.table}" <>
      where_clause(q) <>
      if(q.order, do: " ORDER BY #{q.order}", else: "") <>
      if(q.limit, do: " LIMIT #{q.limit}", else: "") <>
      if(q.offset, do: " OFFSET #{q.offset}", else: "")
  end

  defp where_clause(%{wheres: []}), do: ""

  defp where_clause(%{wheres: w}) do
    " WHERE " <> Enum.map_join(w, " AND ", fn {sql, _} -> sql end)
  end
end

defmodule Laravex.Database.DB do
  @moduledoc "DB facade."
  def table(name), do: Laravex.Database.Query.table(name)
  def select(sql, bindings \\ []), do: Laravex.Database.Connection.query(sql, bindings)
  def statement(sql, bindings \\ []), do: Laravex.Database.Connection.execute(sql, bindings)
  def transaction(fun), do: Laravex.Database.Connection.transaction(fun)
end
