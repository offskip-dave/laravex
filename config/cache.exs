env = &Laravex.Env.get/2
base = File.cwd!()

%{
  "default" => env.("CACHE_STORE", "database"),
  "stores" => %{
    "array" => %{"driver" => "array", "serialize" => false},
    "database" => %{
      "driver" => "database",
      "connection" => env.("DB_CACHE_CONNECTION", nil),
      "table" => env.("DB_CACHE_TABLE", "cache"),
      "lock_connection" => env.("DB_CACHE_LOCK_CONNECTION", nil),
      "lock_table" => env.("DB_CACHE_LOCK_TABLE", nil)
    },
    "file" => %{
      "driver" => "file",
      "path" => Path.join(base, "storage/framework/cache/data"),
      "lock_path" => Path.join(base, "storage/framework/cache/locks")
    },
    "storage" => %{
      "driver" => "storage",
      "disk" => env.("CACHE_STORAGE_DISK", nil),
      "path" => env.("CACHE_STORAGE_PATH", "framework/cache/data")
    },
    "memcached" => %{
      "driver" => "memcached",
      "persistent_id" => env.("MEMCACHED_PERSISTENT_ID", nil),
      "sasl" => [env.("MEMCACHED_USERNAME", nil), env.("MEMCACHED_PASSWORD", nil)],
      "options" => %{},
      "servers" => [
        %{
          "host" => env.("MEMCACHED_HOST", "127.0.0.1"),
          "port" => env.("MEMCACHED_PORT", 11211),
          "weight" => 100
        }
      ]
    },
    "redis" => %{
      "driver" => "redis",
      "connection" => env.("REDIS_CACHE_CONNECTION", "cache"),
      "lock_connection" => env.("REDIS_CACHE_LOCK_CONNECTION", "default")
    },
    "dynamodb" => %{
      "driver" => "dynamodb",
      "key" => env.("AWS_ACCESS_KEY_ID", nil),
      "secret" => env.("AWS_SECRET_ACCESS_KEY", nil),
      "region" => env.("AWS_DEFAULT_REGION", "us-east-1"),
      "table" => env.("DYNAMODB_CACHE_TABLE", "cache"),
      "endpoint" => env.("DYNAMODB_ENDPOINT", nil)
    },
    "octane" => %{"driver" => "octane"},
    "failover" => %{
      "driver" => "failover",
      "stores" => ["database", "array"]
    }
  },
  "prefix" => env.("CACHE_PREFIX", "laravex-cache-")
}
