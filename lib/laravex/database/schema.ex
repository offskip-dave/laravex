defmodule Laravex.Database.Schema do
  @moduledoc "Laravel Schema facade for creating/dropping/altering tables."

  def create(table, fun) when is_binary(table) and is_function(fun, 1) do
    blueprint = Laravex.Database.Blueprint.new(table) |> then(fun)

    Enum.each(Laravex.Database.Blueprint.statements(blueprint), fn sql ->
      Laravex.Database.Connection.execute(sql)
    end)
  end

  @doc "Alter an existing table (SQLite-friendly ADD COLUMN / CREATE INDEX)."
  def table(name, fun) when is_binary(name) and is_function(fun, 1), do: alter(name, fun)

  def alter(table, fun) when is_binary(table) and is_function(fun, 1) do
    blueprint =
      table
      |> Laravex.Database.Blueprint.new()
      |> Map.put(:mode, :alter)
      |> then(fun)

    Enum.each(Laravex.Database.Blueprint.alter_statements(blueprint), fn sql ->
      Laravex.Database.Connection.execute(sql)
    end)
  end

  def drop_if_exists(table) when is_binary(table) do
    Laravex.Database.Connection.execute("DROP TABLE IF EXISTS #{table}")
  end

  def rename(from, to) when is_binary(from) and is_binary(to) do
    Laravex.Database.Connection.execute("ALTER TABLE #{from} RENAME TO #{to}")
  end

  def has_table?(table) do
    rows =
      Laravex.Database.Connection.query(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [table]
      )

    rows != []
  end

  def has_column?(table, column) do
    rows = Laravex.Database.Connection.query("PRAGMA table_info(#{table})")
    Enum.any?(rows, fn row -> Map.get(row, "name") == to_string(column) end)
  rescue
    _ -> false
  end

  def has_index?(table, index_name) do
    rows =
      Laravex.Database.Connection.query(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name=? AND name=?",
        [table, index_name]
      )

    rows != []
  rescue
    _ -> false
  end
end

defmodule Laravex.Database.Blueprint do
  defstruct table: nil, columns: [], indexes: [], mode: :create, drops: []

  def new(table), do: %__MODULE__{table: table, mode: :create}

  def id(bp), do: add(bp, "id INTEGER PRIMARY KEY AUTOINCREMENT")
  def string(bp, name, opts \\ []), do: col(bp, name, "TEXT", opts)
  def text(bp, name, opts \\ []), do: col(bp, name, "TEXT", opts)
  def long_text(bp, name, opts \\ []), do: col(bp, name, "TEXT", opts)
  def medium_text(bp, name, opts \\ []), do: col(bp, name, "TEXT", opts)
  def integer(bp, name, opts \\ []), do: col(bp, name, "INTEGER", opts)
  def big_integer(bp, name, opts \\ []), do: col(bp, name, "INTEGER", opts)
  def unsigned_integer(bp, name, opts \\ []), do: col(bp, name, "INTEGER", opts)
  def unsigned_small_integer(bp, name, opts \\ []), do: col(bp, name, "INTEGER", opts)
  def boolean(bp, name, opts \\ []), do: col(bp, name, "INTEGER", opts)
  def timestamp(bp, name, opts \\ []), do: col(bp, name, "TEXT", opts)
  def timestamps(bp), do: bp |> string("created_at", nullable: true) |> string("updated_at", nullable: true)
  def remember_token(bp), do: string(bp, "remember_token", nullable: true)
  def foreign_id(bp, name, opts \\ []), do: col(bp, name, "INTEGER", opts)

  @doc "Add `deleted_at` nullable timestamp for Eloquex soft deletes."
  def soft_deletes(bp, column \\ "deleted_at") do
    timestamp(bp, column, nullable: true)
  end

  @doc """
  Morph columns `{name}_type` + `{name}_id` with a composite index.

      Blueprint.morphs(bp, \"taggable\")
  """
  def morphs(bp, name, opts \\ []) do
    name = to_string(name)
    index? = Keyword.get(opts, :index, true)

    bp
    |> string("#{name}_type")
    |> integer("#{name}_id")
    |> then(fn b -> if index?, do: index(b, ["#{name}_type", "#{name}_id"]), else: b end)
  end

  def nullable_morphs(bp, name, opts \\ []) do
    name = to_string(name)
    index? = Keyword.get(opts, :index, true)

    bp
    |> string("#{name}_type", nullable: true)
    |> integer("#{name}_id", nullable: true)
    |> then(fn b -> if index?, do: index(b, ["#{name}_type", "#{name}_id"]), else: b end)
  end

  def uuid_morphs(bp, name, opts \\ []) do
    name = to_string(name)
    index? = Keyword.get(opts, :index, true)

    bp
    |> string("#{name}_type")
    |> string("#{name}_id")
    |> then(fn b -> if index?, do: index(b, ["#{name}_type", "#{name}_id"]), else: b end)
  end

  def drop_column(bp, columns) do
    cols = columns |> List.wrap() |> Enum.map(&to_string/1)
    %{bp | drops: bp.drops ++ cols}
  end

  def index(bp, columns, name \\ nil) do
    cols = columns |> List.wrap() |> Enum.map(&to_string/1)
    iname = name || "#{bp.table}_#{Enum.join(cols, "_")}_index"
    %{bp | indexes: [{iname, cols, false} | bp.indexes]}
  end

  def unique(bp, columns, name \\ nil) do
    cols = columns |> List.wrap() |> Enum.map(&to_string/1)
    iname = name || "#{bp.table}_#{Enum.join(cols, "_")}_unique"
    %{bp | indexes: [{iname, cols, true} | bp.indexes]}
  end

  def to_sql(%__MODULE__{table: table, columns: columns}) do
    "CREATE TABLE IF NOT EXISTS #{table} (#{Enum.join(Enum.reverse(columns), ", ")})"
  end

  def statements(%__MODULE__{} = bp) do
    [to_sql(bp) | Enum.map(Enum.reverse(bp.indexes), &index_sql(bp.table, &1))]
  end

  def alter_statements(%__MODULE__{} = bp) do
    adds =
      bp.columns
      |> Enum.reverse()
      |> Enum.map(fn col_sql -> "ALTER TABLE #{bp.table} ADD COLUMN #{col_sql}" end)

    drops =
      Enum.map(bp.drops, fn col -> "ALTER TABLE #{bp.table} DROP COLUMN #{col}" end)

    indexes = Enum.map(Enum.reverse(bp.indexes), &index_sql(bp.table, &1))
    adds ++ drops ++ indexes
  end

  defp index_sql(table, {name, cols, unique?}) do
    unique = if unique?, do: "UNIQUE ", else: ""
    "CREATE #{unique}INDEX IF NOT EXISTS #{name} ON #{table} (#{Enum.join(cols, ", ")})"
  end

  defp col(bp, name, type, opts) do
    nullable = Keyword.get(opts, :nullable, false)
    primary = Keyword.get(opts, :primary, false)
    unique = Keyword.get(opts, :unique, false)

    sql =
      "#{name} #{type}" <>
        if(primary, do: " PRIMARY KEY", else: "") <>
        if(nullable or primary, do: "", else: " NOT NULL") <>
        if(unique, do: " UNIQUE", else: "")

    bp = add(bp, sql)

    cond do
      Keyword.get(opts, :index, false) -> index(bp, [name])
      true -> bp
    end
  end

  defp add(bp, sql), do: %{bp | columns: [sql | bp.columns]}
end
