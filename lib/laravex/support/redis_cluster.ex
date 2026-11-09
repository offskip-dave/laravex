defmodule Laravex.Support.RedisCluster do
  @moduledoc """
  Best-effort Redis Cluster hash-slot routing (not Sentinel).

  Configure `database.redis.clusters.default` as a list of `%{"host" => ..., "port" => ...}`
  and set `REDIS_CLUSTER=true`. Falls back to single-node client otherwise.
  """

  @slots 16_384

  def enabled? do
    to_string(System.get_env("REDIS_CLUSTER") || Laravex.Config.Repository.get("database.redis.options.cluster") || "")
    in ["true", "1", "redis"]
  end

  def slot(key) when is_binary(key) do
    key = hash_tag(key)
    :erlang.phash2(key, @slots)
  end

  def node_for(key, nodes) when is_list(nodes) and nodes != [] do
    idx = rem(slot(key), length(nodes))
    Enum.at(nodes, idx)
  end

  def nodes do
    case Laravex.Config.Repository.get("database.redis.clusters.default") do
      list when is_list(list) and list != [] -> list
      _ ->
        cfg = Laravex.Support.RedisClient.config()
        [%{"host" => cfg.host, "port" => cfg.port}]
    end
  end

  defp hash_tag(key) do
    case Regex.run(~r/\{([^}]+)\}/, key) do
      [_, tag] -> tag
      _ -> key
    end
  end
end
