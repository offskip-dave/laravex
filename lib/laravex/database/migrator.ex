defmodule Laravex.Database.Migrator do
  @moduledoc "Runs migration modules discovered from database/migrations/*.ex."

  def ensure_repository! do
    unless Laravex.Database.Schema.has_table?("migrations") do
      Laravex.Database.Connection.execute("""
      CREATE TABLE IF NOT EXISTS migrations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        migration TEXT NOT NULL,
        batch INTEGER NOT NULL
      )
      """)
    end

    :ok
  end

  def migrate do
    ensure_repository!()
    pending = pending_migrations()
    batch = next_batch()

    Enum.each(pending, fn {name, mod} ->
      IO.puts("Migrating: #{name}")
      mod.up()

      Laravex.Database.Connection.execute(
        "INSERT INTO migrations (migration, batch) VALUES (?, ?)",
        [name, batch]
      )

      IO.puts("Migrated:  #{name}")
    end)

    length(pending)
  end

  def rollback do
    ensure_repository!()
    batch = current_batch()

    if is_nil(batch) do
      0
    else
      rows =
        Laravex.Database.Connection.query(
          "SELECT migration FROM migrations WHERE batch = ? ORDER BY id DESC",
          [batch]
        )

      Enum.each(rows, fn %{"migration" => name} ->
        mod = module_for(name)
        IO.puts("Rolling back: #{name}")
        if mod && function_exported?(mod, :down, 0), do: mod.down()
        Laravex.Database.Connection.execute("DELETE FROM migrations WHERE migration = ?", [name])
      end)

      length(rows)
    end
  end

  def refresh do
    ensure_repository!()

    Laravex.Database.Connection.query("SELECT migration FROM migrations ORDER BY id DESC")
    |> Enum.each(fn %{"migration" => name} ->
      mod = module_for(name)
      if mod && function_exported?(mod, :down, 0), do: mod.down()
    end)

    Laravex.Database.Connection.execute("DELETE FROM migrations")
    migrate()
  end

  def wipe do
    tables()
    |> Enum.reject(&(&1 in ["sqlite_sequence"]))
    |> Enum.each(&Laravex.Database.Schema.drop_if_exists/1)

    :ok
  end

  def fresh do
    wipe()
    migrate()
  end

  def status do
    ensure_repository!()
    ran = MapSet.new(ran_names())

    migration_files()
    |> Enum.map(fn {name, _} ->
      %{migration: name, status: if(MapSet.member?(ran, name), do: "Ran", else: "Pending")}
    end)
  end

  def run_default_migrations, do: migrate()

  def tables do
    Laravex.Database.Connection.query(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
    )
    |> Enum.map(& &1["name"])
  end

  def apply(operations) when is_list(operations) do
    Enum.each(operations, fn
      {:create, name, columns} -> create_from_ops(name, columns)
      _ -> :ok
    end)

    :ok
  end

  def drop(tables) when is_list(tables) do
    Enum.each(tables, &Laravex.Database.Schema.drop_if_exists/1)
    :ok
  end

  defp create_from_ops(name, columns) do
    Laravex.Database.Schema.create(name, fn t ->
      Enum.reduce(columns, t, fn col, bp ->
        case col do
          {:id, :bigserial, _} -> Laravex.Database.Blueprint.id(bp)
          {:string, n} -> Laravex.Database.Blueprint.string(bp, n)
          {:string, n, opts} -> Laravex.Database.Blueprint.string(bp, n, opts)
          {:timestamp, n, opts} -> Laravex.Database.Blueprint.timestamp(bp, n, opts)
          {:remember_token, true} -> Laravex.Database.Blueprint.remember_token(bp)
          {:timestamps, true} -> Laravex.Database.Blueprint.timestamps(bp)
          {:soft_deletes, true} -> Laravex.Database.Blueprint.soft_deletes(bp)
          {:soft_deletes, col} when is_binary(col) -> Laravex.Database.Blueprint.soft_deletes(bp, col)
          {:morphs, name} -> Laravex.Database.Blueprint.morphs(bp, name)
          {:morphs, name, opts} -> Laravex.Database.Blueprint.morphs(bp, name, opts)
          {:nullable_morphs, name} -> Laravex.Database.Blueprint.nullable_morphs(bp, name)
          {:uuid_morphs, name} -> Laravex.Database.Blueprint.uuid_morphs(bp, name)
          {:foreign_id, n, opts} -> Laravex.Database.Blueprint.foreign_id(bp, n, opts)
          {:text, n} -> Laravex.Database.Blueprint.text(bp, n)
          {:text, n, opts} -> Laravex.Database.Blueprint.text(bp, n, opts)
          {:long_text, n} -> Laravex.Database.Blueprint.long_text(bp, n)
          {:long_text, n, opts} -> Laravex.Database.Blueprint.long_text(bp, n, opts)
          {:medium_text, n} -> Laravex.Database.Blueprint.medium_text(bp, n)
          {:medium_text, n, opts} -> Laravex.Database.Blueprint.medium_text(bp, n, opts)
          {:integer, n} -> Laravex.Database.Blueprint.integer(bp, n)
          {:integer, n, opts} -> Laravex.Database.Blueprint.integer(bp, n, opts)
          {:big_integer, n, opts} -> Laravex.Database.Blueprint.big_integer(bp, n, opts)
          {:unsigned_integer, n} -> Laravex.Database.Blueprint.unsigned_integer(bp, n)
          {:unsigned_integer, n, opts} -> Laravex.Database.Blueprint.unsigned_integer(bp, n, opts)
          {:unsigned_small_integer, n} -> Laravex.Database.Blueprint.unsigned_small_integer(bp, n)
          {:timestamp, n} -> Laravex.Database.Blueprint.timestamp(bp, n)
          _ -> bp
        end
      end)
    end)
  end

  defp pending_migrations do
    ran = MapSet.new(ran_names())
    Enum.reject(migration_files(), fn {name, _} -> MapSet.member?(ran, name) end)
  end

  defp ran_names do
    Laravex.Database.Connection.query("SELECT migration FROM migrations")
    |> Enum.map(& &1["migration"])
  end

  defp next_batch do
    case Laravex.Database.Connection.query("SELECT MAX(batch) AS m FROM migrations") do
      [%{"m" => nil}] -> 1
      [%{"m" => m}] when is_integer(m) -> m + 1
      _ -> 1
    end
  end

  defp current_batch do
    case Laravex.Database.Connection.query("SELECT MAX(batch) AS m FROM migrations") do
      [%{"m" => nil}] -> nil
      [%{"m" => m}] -> m
      _ -> nil
    end
  end

  def migration_files do
    dir = Path.join(Laravex.Foundation.Application.base_path(), "database/migrations")

    dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".ex"))
    |> Enum.sort()
    |> Enum.map(fn file ->
      path = Path.join(dir, file)
      name = Path.rootname(file)
      mod = module_from_file(path) || guess_module(name)
      {name, mod}
    end)
    |> Enum.reject(fn {_name, mod} -> is_nil(mod) end)
  end

  defp module_for(name) do
    Enum.find_value(migration_files(), fn {n, m} -> if n == name, do: m end)
  end

  defp module_from_file(path) do
    contents = File.read!(path)

    case Regex.run(~r/defmodule\s+([A-Za-z0-9\.]+)/, contents) do
      [_, mod_name] ->
        mod = Module.concat([mod_name])
        Code.ensure_loaded?(mod)
        mod

      _ ->
        nil
    end
  end

  defp guess_module(name) do
    # 0001_01_01_000000_create_users_table -> CreateUsersTable
    suffix =
      name
      |> String.replace(~r/^\d{4}_\d{2}_\d{2}_\d+_/, "")
      |> Macro.camelize()

    Module.concat([Database.Migrations, suffix])
  end
end
