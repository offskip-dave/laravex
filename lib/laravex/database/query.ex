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

  def or_where(%__MODULE__{} = q, column, value) do
    %{q | wheres: q.wheres ++ [{:or, "#{column} = ?", value}], bindings: q.bindings ++ [value]}
  end

  def or_where(%__MODULE__{} = q, column, op, value) do
    %{q | wheres: q.wheres ++ [{:or, "#{column} #{op} ?", value}], bindings: q.bindings ++ [value]}
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

  def where_between(%__MODULE__{} = q, column, low, high) do
    %{
      q
      | wheres: q.wheres ++ [{"#{column} BETWEEN ? AND ?", :between}],
        bindings: q.bindings ++ [low, high]
    }
  end

  def where_column(%__MODULE__{} = q, first, second), do: where_column(q, first, "=", second)

  def where_column(%__MODULE__{} = q, first, op, second) when is_binary(op) do
    %{q | wheres: q.wheres ++ [{"#{first} #{op} #{second}", :skip}]}
  end

  def where_raw(%__MODULE__{} = q, sql, bindings \\ []) when is_binary(sql) do
    %{q | wheres: q.wheres ++ [{sql, :raw}], bindings: q.bindings ++ List.wrap(bindings)}
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

  def order_by_desc(%__MODULE__{} = q, column), do: order_by(q, column, "desc")

  def limit(%__MODULE__{} = q, n), do: %{q | limit: n}
  def offset(%__MODULE__{} = q, n), do: %{q | offset: n}

  def get(%__MODULE__{} = q) do
    Laravex.Database.Connection.query(to_sql(q), q.bindings)
  end

  def first(%__MODULE__{} = q) do
    q |> limit(1) |> get() |> List.first()
  end

  def value(%__MODULE__{} = q, column) do
    case q |> select([column]) |> first() do
      nil -> nil
      row -> Map.get(row, to_string(column)) || Map.get(row, column)
    end
  end

  def pluck(%__MODULE__{} = q, column) do
    q
    |> select([column])
    |> get()
    |> Enum.map(fn row -> Map.get(row, to_string(column)) || Map.get(row, column) end)
  end

  def max(%__MODULE__{} = q, column), do: aggregate(q, "MAX", column)
  def min(%__MODULE__{} = q, column), do: aggregate(q, "MIN", column)
  def sum(%__MODULE__{} = q, column), do: aggregate(q, "SUM", column)
  def avg(%__MODULE__{} = q, column), do: aggregate(q, "AVG", column)

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

  def insert_all(table, rows) when is_binary(table) and is_list(rows) do
    Enum.map(rows, &insert(table, &1))
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

  @doc "Process results in pages of `size` (offset-based)."
  def chunk(%__MODULE__{} = q, size, fun)
      when is_integer(size) and size > 0 and is_function(fun, 1) do
    do_chunk(q, size, 0, fun)
  end

  defp do_chunk(q, size, page, fun) do
    rows =
      q
      |> offset(page * size)
      |> limit(size)
      |> get()

    cond do
      rows == [] ->
        :ok

      true ->
        fun.(rows)
        if length(rows) < size, do: :ok, else: do_chunk(q, size, page + 1, fun)
    end
  end

  @doc """
  Process results in keyset pages ordered by `column` (default `id`).

      Query.table(\"users\") |> Query.chunk_by_id(100, fn rows -> ... end)
  """
  def chunk_by_id(%__MODULE__{} = q, size, fun, opts \\ [])
      when is_integer(size) and size > 0 and is_function(fun, 1) do
    column = Keyword.get(opts, :column, "id")
    do_chunk_by_id(q, size, fun, to_string(column), nil)
  end

  defp do_chunk_by_id(base_q, size, fun, column, last_id) do
    q =
      if is_nil(last_id) do
        base_q
      else
        where(base_q, column, ">", last_id)
      end

    rows =
      q
      |> order_by(column, "asc")
      |> limit(size)
      |> get()

    cond do
      rows == [] ->
        :ok

      true ->
        fun.(rows)
        last = List.last(rows)
        next_id = Map.get(last, column) || Map.get(last, String.to_atom(column))

        if length(rows) < size or is_nil(next_id),
          do: :ok,
          else: do_chunk_by_id(base_q, size, fun, column, next_id)
    end
  end

  defp aggregate(%__MODULE__{} = q, fn_name, column) do
    sql = "SELECT #{fn_name}(#{column}) AS aggregate FROM #{q.table}#{where_clause(q)}"

    case Laravex.Database.Connection.query(sql, q.bindings) do
      [%{"aggregate" => n}] -> n
      _ -> nil
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
    {sql, _} =
      Enum.reduce(w, {"", true}, fn
        {:or, fragment, _}, {acc, first?} ->
          joiner = if first?, do: "", else: " OR "
          {acc <> joiner <> fragment, false}

        {fragment, _}, {acc, first?} ->
          joiner = if first?, do: "", else: " AND "
          {acc <> joiner <> fragment, false}
      end)

    " WHERE " <> sql
  end
end

defmodule Laravex.Database.DB do
  @moduledoc "DB facade."
  def table(name), do: Laravex.Database.Query.table(name)
  def select(sql, bindings \\ []), do: Laravex.Database.Connection.query(sql, bindings)
  def statement(sql, bindings \\ []), do: Laravex.Database.Connection.execute(sql, bindings)
  def transaction(fun), do: Laravex.Database.Connection.transaction(fun)
end
