defmodule Laravex.Database.Introspection do
  @moduledoc "SQLite schema introspection for artisan db:show / model:show."

  def tables do
    Laravex.Database.Connection.query(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
    )
    |> Enum.map(& &1["name"])
  end

  def columns(table) when is_binary(table) do
    Laravex.Database.Connection.query("PRAGMA table_info(#{quote_ident(table)})")
  end

  def indexes(table) when is_binary(table) do
    Laravex.Database.Connection.query("PRAGMA index_list(#{quote_ident(table)})")
  end

  def table_info(table) when is_binary(table) do
    %{
      name: table,
      columns: columns(table),
      indexes: indexes(table)
    }
  end

  def model_info(mod) when is_atom(mod) do
    Code.ensure_loaded!(mod)

    table =
      cond do
        function_exported?(mod, :table_name, 0) -> mod.table_name()
        true -> nil
      end

    %{
      module: mod,
      table: table,
      soft_deletes?: function_exported?(mod, :soft_deletes?, 0) and mod.soft_deletes?(),
      fillable: if(function_exported?(mod, :fillable, 0), do: mod.fillable(), else: nil),
      guarded: if(function_exported?(mod, :guarded, 0), do: mod.guarded(), else: nil),
      casts: if(function_exported?(mod, :casts, 0), do: mod.casts(), else: %{}),
      appends: if(function_exported?(mod, :appends, 0), do: mod.appends(), else: []),
      relations: if(function_exported?(mod, :relations, 0), do: mod.relations(), else: []),
      columns: if(is_binary(table), do: columns(table), else: [])
    }
  end

  def resolve_model(name) when is_binary(name) do
    candidates = [
      Module.concat(["App", "Models", Macro.camelize(name)]),
      Module.concat([Macro.camelize(name)])
    ]

    Enum.find_value(candidates, fn mod ->
      case Code.ensure_loaded(mod) do
        {:module, ^mod} -> mod
        _ -> nil
      end
    end)
  end

  defp quote_ident(name) do
    "\"" <> String.replace(name, "\"", "\"\"") <> "\""
  end
end
