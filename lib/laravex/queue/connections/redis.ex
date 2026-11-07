defmodule Laravex.Queue.Connections.Redis do
  @moduledoc false
  @behaviour Laravex.Queue.ConnectionAdapter

  @impl true
  def push(job_mod, args, opts) do
    if Keyword.get(opts, :should_queue?, true) do
      push_redis(job_mod, args, opts)
    else
      Laravex.Queue.Worker.push_sync(job_mod, args, opts)
    end
  end

  @doc false
  def push_redis(job_mod, args, opts) do
    payload =
      %{
        "job" => Atom.to_string(job_mod),
        "args" => Laravex.Queue.Worker.encode_args(args),
        "tries" => Keyword.get(opts, :tries, 1),
        "backoff" => Keyword.get(opts, :backoff, 0)
      }
      |> maybe_put_batch(opts)
      |> Laravex.Support.JSON.encode!()

    queue = Keyword.get(opts, :queue, default_queue())
    key = queue_key(queue)

    case Laravex.Support.RedisClient.lpush(key, payload, redis_opts()) do
      :ok -> :ok
      {:error, reason} -> raise "Redis queue error: #{inspect(reason)}"
    end
  end

  @doc false
  def pop(queue \\ nil, timeout \\ 1) do
    key = queue_key(queue || default_queue())

    case Laravex.Support.RedisClient.brpop(key, timeout, redis_opts()) do
      {:ok, payload} -> {:ok, payload}
      :error -> :error
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put_batch(payload, opts) do
    case Keyword.get(opts, :batch_id) do
      id when is_binary(id) and id != "" -> Map.put(payload, "batch_id", id)
      _ -> payload
    end
  end

  defp queue_key(queue), do: "laravex:queue:" <> to_string(queue)

  defp default_queue do
    conn = to_string(Laravex.Config.Repository.get("queue.default", "database"))

    connections = Laravex.Config.Repository.get("queue.connections", %{})
    cfg = Map.get(connections, conn) || Map.get(connections, String.to_atom(conn)) || %{}
    to_string(Map.get(cfg, "queue") || Map.get(cfg, :queue) || "default")
  end

  defp redis_opts do
    conn = to_string(Laravex.Config.Repository.get("queue.default", "database"))

    connections = Laravex.Config.Repository.get("queue.connections", %{})

    cfg =
      Map.get(connections, conn) || Map.get(connections, String.to_atom(conn)) || %{}

    connection = to_string(Map.get(cfg, "connection") || Map.get(cfg, :connection) || "default")
    [connection: connection]
  end
end
