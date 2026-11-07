defmodule Laravex.Session.Drivers.Redis do
  @moduledoc false
  @behaviour Laravex.Session.Driver

  @impl true
  def read(sid), do: read_redis(sid)

  @impl true
  def write(sid, session) do
    payload = session |> :erlang.term_to_binary() |> Base.encode64()
    ttl = lifetime_seconds()

    case Laravex.Support.RedisClient.set(session_key(sid), payload, redis_opts(ex: ttl)) do
      :ok -> :ok
      {:error, reason} -> raise "Redis session error: #{inspect(reason)}"
    end
  rescue
    e -> raise "Redis session error: #{Exception.message(e)}"
  end

  @impl true
  def delete(sid) do
    _ = Laravex.Support.RedisClient.del(session_key(sid), redis_opts())
    :ok
  end

  @impl true
  def gc_expired(_cutoff), do: :ok

  defp read_redis(sid) do
    case Laravex.Support.RedisClient.get(session_key(sid), redis_opts()) do
      nil -> :error
      bin when is_binary(bin) -> {:ok, :erlang.binary_to_term(Base.decode64!(bin))}
      {:error, _} -> :error
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp session_key(sid), do: "laravex:session:" <> sid

  defp lifetime_seconds do
    case Laravex.Config.Repository.get("session.lifetime", 120) do
      n when is_integer(n) -> n * 60
      n when is_binary(n) -> String.to_integer(n) * 60
      _ -> 120 * 60
    end
  end

  defp redis_opts(extra \\ []) do
    [connection: "default"] ++ extra
  end
end
