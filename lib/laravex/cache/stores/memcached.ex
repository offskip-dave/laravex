defmodule Laravex.Cache.Stores.Memcached do
  @moduledoc "Memcached cache store via Memcachex (`CACHE_STORE=memcached`)."
  @behaviour Laravex.Cache.Store

  @impl true
  def get(key, %{array: array}) do
    case Memcache.get(conn(), prefixed(key)) do
      {:ok, bin} when is_binary(bin) -> decode_entry(bin)
      _ -> Map.get(array, key)
    end
  rescue
    _ -> Map.get(array, key)
  end

  @impl true
  def put(key, entry, _state) do
    opts =
      case entry.expires do
        nil -> []
        exp when is_integer(exp) -> [ttl: max(exp - System.system_time(:second), 1)]
      end

    _ = Memcache.set(conn(), prefixed(key), encode_entry(entry), opts)
    :ok
  end

  @impl true
  def forget(key) do
    _ = Memcache.delete(conn(), prefixed(key))
    :ok
  end

  @impl true
  def flush do
    _ = Memcache.flush(conn())
    :ok
  end

  defp conn do
    case Process.whereis(Laravex.Cache.MemcachedConn) do
      nil -> start_conn()
      pid -> pid
    end
  end

  defp start_conn do
    host = System.get_env("MEMCACHED_HOST") || "127.0.0.1"
    port = String.to_integer(System.get_env("MEMCACHED_PORT") || "11211")

    {:ok, pid} = Memcache.start_link(hostname: host, port: port, name: Laravex.Cache.MemcachedConn)
    pid
  end

  defp encode_entry(entry), do: entry |> :erlang.term_to_binary() |> Base.encode64()

  defp decode_entry(bin) do
    :erlang.binary_to_term(Base.decode64!(bin))
  end

  defp prefixed(key) do
    prefix = to_string(Laravex.Config.Repository.get("cache.prefix", "laravex-cache-"))
    prefix <> key
  end
end
