defmodule Laravex.Database.Query do
  @moduledoc "Fluent query builder."

  defstruct table: nil,
            wheres: [],
            bindings: [],
            joins: [],
            groups: [],
            group_raw: [],
            havings: [],
            order: nil,
            unions: [],
            limit: nil,
            offset: nil,
            distinct?: false,
            columns: ["*"],
            lock: nil,
            connection: nil

  def table(name), do: %__MODULE__{table: name}

  @doc "Use a named database connection for this query (Laravel `DB::connection`)."
  def connection(%__MODULE__{} = q, name), do: %{q | connection: name}

  def select(%__MODULE__{} = q, cols) when is_list(cols), do: %{q | columns: cols}

  @doc "Append columns without replacing (Laravel `addSelect`). Replaces bare `*`."
  def add_select(%__MODULE__{} = q, cols) when is_list(cols) do
    cols = Enum.map(cols, &to_string/1)

    columns =
      case q.columns do
        ["*"] -> cols
        existing -> existing ++ cols
      end

    %{q | columns: columns}
  end

  def add_select(%__MODULE__{} = q, col), do: add_select(q, [col])

  def distinct(%__MODULE__{} = q, value \\ true), do: %{q | distinct?: value == true}

  @doc "Laravel `when` — apply `fun` when `condition` is truthy (Elixir-reserved name avoided)."
  def when_cond(%__MODULE__{} = q, condition, fun) when is_function(fun, 1) do
    if truthy_condition?(condition), do: fun.(q), else: q
  end

  @doc "Laravel `unless` — apply `fun` when `condition` is falsy."
  def unless_cond(%__MODULE__{} = q, condition, fun) when is_function(fun, 1) do
    if truthy_condition?(condition), do: q, else: fun.(q)
  end

  def latest(%__MODULE__{} = q, column \\ "created_at"), do: order_by_desc(q, column)
  def oldest(%__MODULE__{} = q, column \\ "created_at"), do: order_by(q, column, "asc")

  defp truthy_condition?(v) when v in [false, nil, 0, "", "0"], do: false
  defp truthy_condition?(_), do: true

  def select_raw(%__MODULE__{} = q, sql) when is_binary(sql) do
    %{q | columns: q.columns ++ [sql]}
  end

  def group_by(%__MODULE__{} = q, columns) when is_list(columns) do
    %{q | groups: q.groups ++ Enum.map(columns, &to_string/1)}
  end

  def group_by(%__MODULE__{} = q, column), do: group_by(q, [column])

  def having(%__MODULE__{} = q, column, value) do
    %{
      q
      | havings: q.havings ++ [{"#{column} = ?", value}],
        bindings: q.bindings ++ [value]
    }
  end

  def having(%__MODULE__{} = q, column, op, value) do
    %{
      q
      | havings: q.havings ++ [{"#{column} #{op} ?", value}],
        bindings: q.bindings ++ [value]
    }
  end

  def having_raw(%__MODULE__{} = q, sql, bindings \\ []) when is_binary(sql) do
    %{
      q
      | havings: q.havings ++ [{sql, :raw}],
        bindings: q.bindings ++ List.wrap(bindings)
    }
  end

  def or_having(%__MODULE__{} = q, column, value) do
    %{
      q
      | havings: q.havings ++ [{:or, "#{column} = ?", value}],
        bindings: q.bindings ++ [value]
    }
  end

  def or_having(%__MODULE__{} = q, column, op, value) do
    %{
      q
      | havings: q.havings ++ [{:or, "#{column} #{op} ?", value}],
        bindings: q.bindings ++ [value]
    }
  end

  def or_having_raw(%__MODULE__{} = q, sql, bindings \\ []) when is_binary(sql) do
    %{
      q
      | havings: q.havings ++ [{:or, sql, :raw}],
        bindings: q.bindings ++ List.wrap(bindings)
    }
  end

  @doc "INNER JOIN `table` ON `left` `op` `right` (columns may be qualified)."
  def join(%__MODULE__{} = q, table, left, right), do: join(q, table, left, "=", right)

  def join(%__MODULE__{} = q, table, left, op, right) when is_binary(op) do
    %{q | joins: q.joins ++ [{:inner, to_string(table), to_string(left), op, to_string(right)}]}
  end

  @doc "LEFT JOIN `table` ON `left` `op` `right`."
  def left_join(%__MODULE__{} = q, table, left, right), do: left_join(q, table, left, "=", right)

  def left_join(%__MODULE__{} = q, table, left, op, right) when is_binary(op) do
    %{q | joins: q.joins ++ [{:left, to_string(table), to_string(left), op, to_string(right)}]}
  end

  @doc "RIGHT JOIN `table` ON `left` `op` `right`."
  def right_join(%__MODULE__{} = q, table, left, right), do: right_join(q, table, left, "=", right)

  def right_join(%__MODULE__{} = q, table, left, op, right) when is_binary(op) do
    %{q | joins: q.joins ++ [{:right, to_string(table), to_string(left), op, to_string(right)}]}
  end

  @doc "FROM a subquery aliased as `as` (Laravel `fromSub`)."
  def from_sub(%__MODULE__{} = q, %__MODULE__{} = sub, as) do
    {sql, bindings} = subquery_body(sub)
    as = to_string(as)
    %{q | table: "(#{sql}) AS #{as}", bindings: bindings ++ q.bindings}
  end

  @doc "INNER JOIN a subquery aliased as `as` (Laravel `joinSub`)."
  def join_sub(%__MODULE__{} = q, %__MODULE__{} = sub, as, left, right),
    do: join_sub(q, sub, as, left, "=", right)

  def join_sub(%__MODULE__{} = q, %__MODULE__{} = sub, as, left, op, right)
      when is_binary(op) do
    {sql, bindings} = subquery_body(sub)
    as = to_string(as)

    %{
      q
      | joins:
          q.joins ++
            [
              {:inner, {:subquery, sql, as, bindings}, to_string(left), op, to_string(right)}
            ]
    }
  end

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

  def or_where_null(%__MODULE__{} = q, column) do
    %{q | wheres: q.wheres ++ [{:or, "#{column} IS NULL", :skip}]}
  end

  def or_where_not_null(%__MODULE__{} = q, column) do
    %{q | wheres: q.wheres ++ [{:or, "#{column} IS NOT NULL", :skip}]}
  end

  @doc "Add an EXISTS subquery (Laravel `whereExists`). `fun` receives a fresh Query."
  def where_exists(%__MODULE__{} = q, fun) when is_function(fun, 1) do
    sub = fun.(%__MODULE__{table: q.table, columns: ["1"]})
    {clause, bindings} = to_where_sql(sub)
    cols = Enum.join(sub.columns || ["1"], ", ")
    sql = "EXISTS (SELECT #{cols} FROM #{sub.table}" <> if(clause == "", do: "", else: " WHERE " <> clause) <> ")"
    %{q | wheres: q.wheres ++ [{sql, :raw}], bindings: q.bindings ++ bindings}
  end

  def or_where_exists(%__MODULE__{} = q, fun) when is_function(fun, 1) do
    sub = fun.(%__MODULE__{table: q.table, columns: ["1"]})
    {clause, bindings} = to_where_sql(sub)
    cols = Enum.join(sub.columns || ["1"], ", ")
    sql = "EXISTS (SELECT #{cols} FROM #{sub.table}" <> if(clause == "", do: "", else: " WHERE " <> clause) <> ")"
    %{q | wheres: q.wheres ++ [{:or, sql, :raw}], bindings: q.bindings ++ bindings}
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

  def where_not_in(%__MODULE__{} = q, column, values) when is_list(values) do
    if values == [] do
      q
    else
      placeholders = Enum.map_join(values, ", ", fn _ -> "?" end)

      %{
        q
        | wheres: q.wheres ++ [{"#{column} NOT IN (#{placeholders})", :in}],
          bindings: q.bindings ++ values
      }
    end
  end

  def or_where_in(%__MODULE__{} = q, column, values) when is_list(values) do
    if values == [] do
      %{q | wheres: q.wheres ++ [{:or, "1 = 0", :skip}]}
    else
      placeholders = Enum.map_join(values, ", ", fn _ -> "?" end)

      %{
        q
        | wheres: q.wheres ++ [{:or, "#{column} IN (#{placeholders})", :in}],
          bindings: q.bindings ++ values
      }
    end
  end

  def or_where_not_in(%__MODULE__{} = q, column, values) when is_list(values) do
    if values == [] do
      q
    else
      placeholders = Enum.map_join(values, ", ", fn _ -> "?" end)

      %{
        q
        | wheres: q.wheres ++ [{:or, "#{column} NOT IN (#{placeholders})", :in}],
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

  def where_not_between(%__MODULE__{} = q, column, low, high) do
    %{
      q
      | wheres: q.wheres ++ [{"#{column} NOT BETWEEN ? AND ?", :between}],
        bindings: q.bindings ++ [low, high]
    }
  end

  def or_where_between(%__MODULE__{} = q, column, low, high) do
    %{
      q
      | wheres: q.wheres ++ [{:or, "#{column} BETWEEN ? AND ?", :between}],
        bindings: q.bindings ++ [low, high]
    }
  end

  def or_where_not_between(%__MODULE__{} = q, column, low, high) do
    %{
      q
      | wheres: q.wheres ++ [{:or, "#{column} NOT BETWEEN ? AND ?", :between}],
        bindings: q.bindings ++ [low, high]
    }
  end

  def where_like(%__MODULE__{} = q, column, pattern) when is_binary(pattern) do
    %{q | wheres: q.wheres ++ [{"#{column} LIKE ?", pattern}], bindings: q.bindings ++ [pattern]}
  end

  def or_where_like(%__MODULE__{} = q, column, pattern) when is_binary(pattern) do
    %{
      q
      | wheres: q.wheres ++ [{:or, "#{column} LIKE ?", pattern}],
        bindings: q.bindings ++ [pattern]
    }
  end

  @doc "Compare the date portion of a column (SQLite `date()`)."
  def where_date(%__MODULE__{} = q, column, value) do
    date = normalize_sql_date(value)
    %{q | wheres: q.wheres ++ [{"date(#{column}) = ?", date}], bindings: q.bindings ++ [date]}
  end

  def where_year(%__MODULE__{} = q, column, year) do
    y = to_string(year)
    %{q | wheres: q.wheres ++ [{"strftime('%Y', #{column}) = ?", y}], bindings: q.bindings ++ [y]}
  end

  def where_month(%__MODULE__{} = q, column, month) do
    m = month |> to_string() |> String.pad_leading(2, "0")
    %{q | wheres: q.wheres ++ [{"strftime('%m', #{column}) = ?", m}], bindings: q.bindings ++ [m]}
  end

  def where_day(%__MODULE__{} = q, column, day) do
    d = day |> to_string() |> String.pad_leading(2, "0")
    %{q | wheres: q.wheres ++ [{"strftime('%d', #{column}) = ?", d}], bindings: q.bindings ++ [d]}
  end

  @doc "Compare the time portion of a column (SQLite `time()`)."
  def where_time(%__MODULE__{} = q, column, value) do
    time = normalize_sql_time(value)
    %{q | wheres: q.wheres ++ [{"time(#{column}) = ?", time}], bindings: q.bindings ++ [time]}
  end

  def or_where_date(%__MODULE__{} = q, column, value) do
    date = normalize_sql_date(value)

    %{
      q
      | wheres: q.wheres ++ [{:or, "date(#{column}) = ?", date}],
        bindings: q.bindings ++ [date]
    }
  end

  def or_where_year(%__MODULE__{} = q, column, year) do
    y = to_string(year)

    %{
      q
      | wheres: q.wheres ++ [{:or, "strftime('%Y', #{column}) = ?", y}],
        bindings: q.bindings ++ [y]
    }
  end

  def or_where_month(%__MODULE__{} = q, column, month) do
    m = month |> to_string() |> String.pad_leading(2, "0")

    %{
      q
      | wheres: q.wheres ++ [{:or, "strftime('%m', #{column}) = ?", m}],
        bindings: q.bindings ++ [m]
    }
  end

  def or_where_day(%__MODULE__{} = q, column, day) do
    d = day |> to_string() |> String.pad_leading(2, "0")

    %{
      q
      | wheres: q.wheres ++ [{:or, "strftime('%d', #{column}) = ?", d}],
        bindings: q.bindings ++ [d]
    }
  end

  def or_where_time(%__MODULE__{} = q, column, value) do
    time = normalize_sql_time(value)

    %{
      q
      | wheres: q.wheres ++ [{:or, "time(#{column}) = ?", time}],
        bindings: q.bindings ++ [time]
    }
  end

  defp normalize_sql_date(%Date{} = d), do: Date.to_iso8601(d)
  defp normalize_sql_date(%DateTime{} = dt), do: DateTime.to_date(dt) |> Date.to_iso8601()
  defp normalize_sql_date(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt) |> Date.to_iso8601()
  defp normalize_sql_date(v) when is_binary(v), do: String.slice(v, 0, 10)
  defp normalize_sql_date(v), do: to_string(v)

  defp normalize_sql_time(%Time{} = t), do: Time.to_iso8601(t) |> String.slice(0, 8)
  defp normalize_sql_time(%DateTime{} = dt), do: DateTime.to_time(dt) |> normalize_sql_time()
  defp normalize_sql_time(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_time(ndt) |> normalize_sql_time()
  defp normalize_sql_time(v) when is_binary(v) do
    cond do
      String.contains?(v, "T") -> v |> String.split("T") |> List.last() |> String.slice(0, 8)
      String.contains?(v, " ") -> v |> String.split(" ") |> List.last() |> String.slice(0, 8)
      true -> String.slice(v, 0, 8)
    end
  end
  defp normalize_sql_time(v), do: to_string(v)

  def where_column(%__MODULE__{} = q, first, second), do: where_column(q, first, "=", second)

  def where_column(%__MODULE__{} = q, first, op, second) when is_binary(op) do
    %{q | wheres: q.wheres ++ [{"#{first} #{op} #{second}", :skip}]}
  end

  def or_where_column(%__MODULE__{} = q, first, second), do: or_where_column(q, first, "=", second)

  def or_where_column(%__MODULE__{} = q, first, op, second) when is_binary(op) do
    %{q | wheres: q.wheres ++ [{:or, "#{first} #{op} #{second}", :skip}]}
  end

  def where_raw(%__MODULE__{} = q, sql, bindings \\ []) when is_binary(sql) do
    %{q | wheres: q.wheres ++ [{sql, :raw}], bindings: q.bindings ++ List.wrap(bindings)}
  end

  def or_where_raw(%__MODULE__{} = q, sql, bindings \\ []) when is_binary(sql) do
    %{q | wheres: q.wheres ++ [{:or, sql, :raw}], bindings: q.bindings ++ List.wrap(bindings)}
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

  @doc "Raw ORDER BY fragment (Laravel `orderByRaw`)."
  def order_by_raw(%__MODULE__{} = q, sql, bindings \\ []) when is_binary(sql) do
    %{q | order: sql, bindings: q.bindings ++ List.wrap(bindings)}
  end

  @doc "Clear ordering (Laravel `reorder`)."
  def reorder(%__MODULE__{} = q), do: %{q | order: nil}

  @doc "ORDER BY RANDOM()/RAND() (Laravel `inRandomOrder`; MySQL uses `RAND()`)."
  def in_random_order(%__MODULE__{} = q),
    do: order_by_raw(q, Laravex.Database.Connection.random_order_fragment())

  def group_by_raw(%__MODULE__{} = q, sql) when is_binary(sql) do
    %{q | group_raw: q.group_raw ++ [sql]}
  end

  @doc "Append a UNION query (Laravel `union`)."
  def union(%__MODULE__{} = q, %__MODULE__{} = other) do
    %{q | unions: q.unions ++ [{:union, other}]}
  end

  def union_all(%__MODULE__{} = q, %__MODULE__{} = other) do
    %{q | unions: q.unions ++ [{:union_all, other}]}
  end

  def lock_for_update(%__MODULE__{} = q), do: %{q | lock: :update}
  def shared_lock(%__MODULE__{} = q), do: %{q | lock: :shared}

  def limit(%__MODULE__{} = q, n), do: %{q | limit: n}
  def offset(%__MODULE__{} = q, n), do: %{q | offset: n}

  @doc "Paginate by page number (Laravel `forPage`). 1-based."
  def for_page(%__MODULE__{} = q, page, per_page \\ 15)
      when is_integer(page) and page >= 1 and is_integer(per_page) and per_page > 0 do
    q
    |> offset((page - 1) * per_page)
    |> limit(per_page)
  end

  def get(%__MODULE__{} = q) do
    on_connection(q, fn ->
      Laravex.Database.Connection.query(to_sql(q), all_bindings(q))
    end)
  end

  defp on_connection(%__MODULE__{connection: nil}, fun), do: fun.()

  defp on_connection(%__MODULE__{connection: name}, fun) do
    Laravex.Database.Connection.using_connection(name, fun)
  end

  defp all_bindings(%__MODULE__{} = q) do
    join_bindings =
      Enum.flat_map(q.joins || [], fn
        {_kind, {:subquery, _sql, _as, bindings}, _, _, _} -> bindings
        _ -> []
      end)

    base = join_bindings ++ (q.bindings || [])

    Enum.reduce(q.unions || [], base, fn {_kind, other}, acc ->
      acc ++ all_bindings(other)
    end)
  end

  defp subquery_body(%__MODULE__{} = sub) do
    {build_sql(sub), all_bindings(sub)}
  end

  @doc """
  Cursor pagination (keyset on `id` or `column`).

  Returns `%{data:, next_cursor:, prev_cursor:, path:}`.
  """
  def cursor_paginate(%__MODULE__{} = q, per_page \\ 15, opts \\ [])
      when is_integer(per_page) and per_page > 0 do
    column = to_string(Keyword.get(opts, :column, "id"))
    cursor = Keyword.get(opts, :cursor)
    path = Keyword.get(opts, :path, "/")

    q =
      q
      |> order_by(column, "asc")
      |> then(fn base ->
        if is_nil(cursor) or cursor == "" do
          base
        else
          where(base, column, ">", cursor)
        end
      end)

    rows = q |> limit(per_page + 1) |> get()
    has_more = length(rows) > per_page
    data = Enum.take(rows, per_page)

    next_cursor =
      if has_more do
        last = List.last(data)

        Map.get(last, column) || Map.get(last, String.to_atom(column))
      end

    %{
      data: data,
      next_cursor: next_cursor,
      prev_cursor: cursor,
      path: path
    }
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

  @doc """
  Insert or ignore on UNIQUE/PRIMARY conflict (SQLite `INSERT OR IGNORE`).
  """
  def insert_or_ignore(table, attrs) when is_binary(table) and is_map(attrs) do
    cols = Map.keys(attrs) |> Enum.map(&to_string/1)
    vals = Enum.map(cols, &Map.get(attrs, &1) || Map.get(attrs, String.to_atom(&1)))
    placeholders = Enum.map_join(cols, ", ", fn _ -> "?" end)

    Laravex.Database.Connection.execute(
      "INSERT OR IGNORE INTO #{table} (#{Enum.join(cols, ", ")}) VALUES (#{placeholders})",
      vals
    )

    :ok
  end

  def insert_or_ignore(table, rows) when is_binary(table) and is_list(rows) do
    Enum.each(rows, &insert_or_ignore(table, &1))
    :ok
  end

  @doc """
  Upsert rows on conflict of `unique_by` columns, updating `update` columns
  (SQLite `ON CONFLICT ... DO UPDATE`).

      Query.upsert(\"users\", [%{\"email\" => \"a@b.c\", \"name\" => \"A\"}], [\"email\"], [\"name\"])
  """
  def upsert(table, rows, unique_by, update \\ nil)
      when is_binary(table) and is_list(rows) do
    unique_by = unique_by |> List.wrap() |> Enum.map(&to_string/1)

    Enum.each(List.wrap(rows), fn attrs ->
      attrs = stringify_attrs(attrs)
      cols = Map.keys(attrs)
      vals = Enum.map(cols, &Map.get(attrs, &1))
      placeholders = Enum.map_join(cols, ", ", fn _ -> "?" end)

      update_cols =
        case update do
          nil -> Enum.reject(cols, &(&1 in unique_by))
          list -> list |> List.wrap() |> Enum.map(&to_string/1)
        end

      conflict = Enum.join(unique_by, ", ")

      sql =
        if update_cols == [] do
          "INSERT INTO #{table} (#{Enum.join(cols, ", ")}) VALUES (#{placeholders}) ON CONFLICT(#{conflict}) DO NOTHING"
        else
          sets = Enum.map_join(update_cols, ", ", fn c -> "#{c} = excluded.#{c}" end)

          "INSERT INTO #{table} (#{Enum.join(cols, ", ")}) VALUES (#{placeholders}) ON CONFLICT(#{conflict}) DO UPDATE SET #{sets}"
        end

      Laravex.Database.Connection.execute(sql, vals)
    end)

    :ok
  end

  defp stringify_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end

  def update(%__MODULE__{} = q, attrs) when is_map(attrs) do
    on_connection(q, fn ->
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
    end)
  end

  def delete(%__MODULE__{} = q) do
    on_connection(q, fn ->
      Laravex.Database.Connection.execute("DELETE FROM #{q.table}#{where_clause(q)}", q.bindings)
    end)
  end

  def count(%__MODULE__{} = q) do
    on_connection(q, fn ->
      sql = "SELECT COUNT(*) AS aggregate FROM #{q.table}#{join_clause(q)}#{where_clause(q)}"

      case Laravex.Database.Connection.query(sql, q.bindings) do
        [%{"aggregate" => n}] -> n
        _ -> 0
      end
    end)
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
    sql =
      "SELECT #{fn_name}(#{column}) AS aggregate FROM #{q.table}#{join_clause(q)}#{where_clause(q)}"

    case Laravex.Database.Connection.query(sql, q.bindings) do
      [%{"aggregate" => n}] -> n
      _ -> nil
    end
  end

  def to_sql(%__MODULE__{} = q), do: build_sql(q)

  defp build_sql(%__MODULE__{} = q) do
    cols = Enum.join(q.columns, ", ")
    distinct = if Map.get(q, :distinct?), do: "DISTINCT ", else: ""

    base =
      "SELECT #{distinct}#{cols} FROM #{q.table}" <>
        join_clause(q) <>
        where_clause(q) <>
        group_clause(q) <>
        having_clause(q) <>
        if(q.order, do: " ORDER BY #{q.order}", else: "") <>
        if(q.limit, do: " LIMIT #{q.limit}", else: "") <>
        if(q.offset, do: " OFFSET #{q.offset}", else: "") <>
        lock_clause(q)

    Enum.reduce(q.unions || [], base, fn
      {:union, other}, acc ->
        acc <> " UNION " <> wrap_union_sql(other)

      {:union_all, other}, acc ->
        acc <> " UNION ALL " <> wrap_union_sql(other)
    end)
  end

  defp wrap_union_sql(%__MODULE__{} = q), do: "(" <> build_sql(%{q | unions: []}) <> ")"

  defp lock_clause(%{lock: :update}), do: ""
  defp lock_clause(%{lock: :shared}), do: ""
  defp lock_clause(_), do: ""

  defp group_clause(q) do
    groups = Map.get(q, :groups) || []
    raw = Map.get(q, :group_raw) || []
    parts = Enum.map(groups, &to_string/1) ++ List.wrap(raw)
    if parts == [], do: "", else: " GROUP BY #{Enum.join(parts, ", ")}"
  end

  defp having_clause(%{havings: []}), do: ""
  defp having_clause(%{havings: nil}), do: ""

  defp having_clause(%{havings: havings}) do
    {sql, _} =
      Enum.reduce(havings, {"", true}, fn
        {:or, fragment, _}, {acc, first?} ->
          joiner = if first?, do: "", else: " OR "
          {acc <> joiner <> fragment, false}

        {fragment, _}, {acc, first?} ->
          joiner = if first?, do: "", else: " AND "
          {acc <> joiner <> fragment, false}

        fragment, {acc, first?} when is_binary(fragment) ->
          joiner = if first?, do: "", else: " AND "
          {acc <> joiner <> fragment, false}
      end)

    " HAVING " <> sql
  end

  defp join_clause(%{joins: []}), do: ""
  defp join_clause(%{joins: nil}), do: ""

  defp join_clause(%{joins: joins}) do
    Enum.map_join(joins, "", fn
      {:inner, table, left, op, right} when is_binary(table) ->
        " INNER JOIN #{table} ON #{left} #{op} #{right}"

      {:inner, {:subquery, sql, as, _bindings}, left, op, right} ->
        " INNER JOIN (#{sql}) AS #{as} ON #{left} #{op} #{right}"

      {:left, table, left, op, right} when is_binary(table) ->
        " LEFT JOIN #{table} ON #{left} #{op} #{right}"

      {:left, {:subquery, sql, as, _bindings}, left, op, right} ->
        " LEFT JOIN (#{sql}) AS #{as} ON #{left} #{op} #{right}"

      {:right, table, left, op, right} when is_binary(table) ->
        " RIGHT JOIN #{table} ON #{left} #{op} #{right}"

      {:right, {:subquery, sql, as, _bindings}, left, op, right} ->
        " RIGHT JOIN (#{sql}) AS #{as} ON #{left} #{op} #{right}"
    end)
  end

  @doc "Return `{where_sql_without_keyword, bindings}` for embedding in subqueries."
  def to_where_sql(%__MODULE__{wheres: []}), do: {"", []}

  def to_where_sql(%__MODULE__{} = q) do
    clause = where_clause(q) |> String.replace_prefix(" WHERE ", "")
    {clause, q.bindings}
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
