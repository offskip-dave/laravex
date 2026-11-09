defmodule Laravex.Pennant do
  @moduledoc """
  Laravel Pennant lite — feature flags (array or database store).

      Laravex.Pennant.activate("new-checkout")
      Laravex.Pennant.active?("new-checkout")
  """

  @table :laravex_pennant

  def ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        _ = :ets.new(@table, [:named_table, :public, :set])
        :ok
      rescue
        ArgumentError -> :ok
      end
    else
      :ok
    end
  end

  def active?(feature, scope \\ :global) do
    ensure()
    key = key(feature, scope)

    case store() do
      :database -> db_active?(key)
      _ -> match?([{^key, true}], :ets.lookup(@table, key))
    end
  end

  def inactive?(feature, scope \\ :global), do: not active?(feature, scope)

  def activate(feature, scope \\ :global) do
    ensure()
    key = key(feature, scope)

    case store() do
      :database -> db_set(key, true)
      _ -> :ets.insert(@table, {key, true})
    end

    :ok
  end

  def deactivate(feature, scope \\ :global) do
    ensure()
    key = key(feature, scope)

    case store() do
      :database -> db_set(key, false)
      _ -> :ets.insert(@table, {key, false})
    end

    :ok
  end

  def forget(feature, scope \\ :global) do
    ensure()
    key = key(feature, scope)

    case store() do
      :database ->
        _ = Laravex.Database.Connection.execute("DELETE FROM features WHERE name = ?", [key])
        :ok

      _ ->
        :ets.delete(@table, key)
        :ok
    end
  end

  defp store do
    case to_string(Laravex.Config.Repository.get("pennant.store") || System.get_env("PENNANT_STORE") || "array") do
      "database" -> :database
      _ -> :array
    end
  end

  defp key(feature, :global), do: to_string(feature)
  defp key(feature, scope), do: "#{feature}:#{inspect(scope)}"

  defp db_active?(key) do
    case Laravex.Database.Connection.query("SELECT active FROM features WHERE name = ? LIMIT 1", [key]) do
      [%{"active" => v}] when v in [1, "1", true, "true"] -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp db_set(key, active) do
    val = if active, do: 1, else: 0

    Laravex.Database.Connection.execute(
      "INSERT INTO features (name, active) VALUES (?, ?) ON CONFLICT(name) DO UPDATE SET active = excluded.active",
      [key, val]
    )
  rescue
    _ ->
      # Table may not exist yet — fall back to ETS
      ensure()
      :ets.insert(@table, {key, active})
      :ok
  end
end
