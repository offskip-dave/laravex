defmodule Laravex.Cache.Stores.Database do
  @moduledoc false
  @behaviour Laravex.Cache.Store

  @impl true
  def get(key, %{array: array}), do: read_db(key) || Map.get(array, key)

  @impl true
  def put(key, entry, _state) do
    write_db(key, entry)
    :ok
  end

  @impl true
  def forget(key) do
    if Laravex.Database.Schema.has_table?("cache") do
      Laravex.Database.Connection.execute("DELETE FROM cache WHERE key = ?", [key])
    end

    :ok
  end

  @impl true
  def flush, do: :ok

  defp write_db(key, entry) do
    if Laravex.Database.Schema.has_table?("cache") do
      Laravex.Database.Connection.execute("DELETE FROM cache WHERE key = ?", [key])

      Laravex.Database.Connection.execute(
        "INSERT INTO cache (key, value, expiration) VALUES (?, ?, ?)",
        [key, :erlang.term_to_binary(entry) |> Base.encode64(), entry.expires || 0]
      )
    end
  end

  defp read_db(key) do
    if Laravex.Database.Schema.has_table?("cache") do
      case Laravex.Database.Connection.query("SELECT value FROM cache WHERE key = ?", [key]) do
        [%{"value" => bin}] -> :erlang.binary_to_term(Base.decode64!(bin))
        _ -> nil
      end
    else
      nil
    end
  end
end
