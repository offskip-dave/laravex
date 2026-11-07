defmodule Laravex.Database.Schema do
  @moduledoc "Laravel Schema facade for creating/dropping tables."

  def create(table, fun) when is_binary(table) and is_function(fun, 1) do
    blueprint = Laravex.Database.Blueprint.new(table) |> then(fun)
    Laravex.Database.Connection.execute(Laravex.Database.Blueprint.to_sql(blueprint))
  end

  def drop_if_exists(table) when is_binary(table) do
    Laravex.Database.Connection.execute("DROP TABLE IF EXISTS #{table}")
  end

  def has_table?(table) do
    rows =
      Laravex.Database.Connection.query(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [table]
      )

    rows != []
  end
end

defmodule Laravex.Database.Blueprint do
  defstruct table: nil, columns: [], indexes: []

  def new(table), do: %__MODULE__{table: table}

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

  def to_sql(%__MODULE__{table: table, columns: columns}) do
    "CREATE TABLE IF NOT EXISTS #{table} (#{Enum.join(Enum.reverse(columns), ", ")})"
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

    add(bp, sql)
  end

  defp add(bp, sql), do: %{bp | columns: [sql | bp.columns]}
end
