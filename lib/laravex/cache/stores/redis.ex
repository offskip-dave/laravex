defmodule Laravex.Cache.Stores.Redis do
  @moduledoc false
  @behaviour Laravex.Cache.Store

  @impl true
  def get(key, %{array: array}) do
    case read_redis(key) do
      nil -> Map.get(array, key)
      entry -> entry
    end
  end

  @impl true
  def put(key, entry, _state) do
    write_redis(key, entry)
    :ok
  end

  @impl true
  def forget(key) do
    _ = Laravex.Support.RedisClient.del(prefixed(key), redis_opts())
    :ok
  end

  @impl true
  def flush, do: :ok

  defp read_redis(key) do
    # RedisClient.get/2 returns the RESP value directly (or {:error, _}).
    case Laravex.Support.RedisClient.get(prefixed(key), redis_opts()) do
      nil -> nil
      bin when is_binary(bin) -> decode_entry(bin)
      {:error, _} -> nil
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp write_redis(key, entry) do
    bin = encode_entry(entry)
    opts = redis_opts()

    opts =
      case entry.expires do
        nil -> opts
        0 -> opts
        exp when is_integer(exp) ->
          ttl = max(exp - System.system_time(:second), 1)
          Keyword.put(opts, :ex, ttl)
      end

    case Laravex.Support.RedisClient.set(prefixed(key), bin, opts) do
      :ok -> :ok
      {:error, reason} -> raise "Redis cache error: #{inspect(reason)}"
    end
  rescue
    e in [RuntimeError] -> reraise e, __STACKTRACE__
    e -> raise "Redis cache error: #{Exception.message(e)}"
  end

  defp encode_entry(entry) do
    entry |> :erlang.term_to_binary() |> Base.encode64()
  end

  defp decode_entry(bin) do
    :erlang.binary_to_term(Base.decode64!(bin))
  end

  defp prefixed(key) do
    prefix = to_string(Laravex.Config.Repository.get("cache.prefix", "laravex-cache-"))
    prefix <> key
  end

  defp redis_opts do
    stores = Laravex.Config.Repository.get("cache.stores", %{})
    name = to_string(Laravex.Config.Repository.get("cache.default", "array"))

    cfg =
      Map.get(stores, name) || Map.get(stores, String.to_atom(name)) || %{}

    conn = to_string(Map.get(cfg, "connection") || Map.get(cfg, :connection) || "cache")
    [connection: conn]
  end
end
