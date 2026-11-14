env = &Laravex.Env.get/2
base = File.cwd!()

# Keep false PDO-style option values; drop only nil (Laravel #6879).
pdo_options =
  %{"ssl_ca" => env.("MYSQL_ATTR_SSL_CA", nil)}
  |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  |> Map.new()

%{
  "default" => env.("DB_CONNECTION", "sqlite"),
  "connections" => %{
    "sqlite" => %{
      "driver" => "sqlite",
      "client" => env.("DB_CLIENT", "cli"),
      "url" => env.("DB_URL", nil),
      "database" => env.("DB_DATABASE", Path.join(base, "database/database.sqlite")),
      "prefix" => "",
      "pool" => env.("DB_POOL_SIZE", 5),
      "foreign_key_constraints" => env.("DB_FOREIGN_KEYS", true),
      "busy_timeout" => nil,
      "journal_mode" => nil,
      "synchronous" => nil,
      "transaction_mode" => "DEFERRED"
    },
    "mysql" => %{
      "driver" => "mysql",
      "client" => env.("DB_CLIENT", "cli"),
      "url" => env.("DB_URL", nil),
      "host" => env.("DB_HOST", "127.0.0.1"),
      "port" => env.("DB_PORT", "3306"),
      "database" => env.("DB_DATABASE", "laravex"),
      "username" => env.("DB_USERNAME", "root"),
      "password" => env.("DB_PASSWORD", ""),
      "unix_socket" => env.("DB_SOCKET", ""),
      "charset" => env.("DB_CHARSET", "utf8mb4"),
      "collation" => env.("DB_COLLATION", "utf8mb4_unicode_ci"),
      "prefix" => "",
      "pool" => env.("DB_POOL_SIZE", 5),
      "prefix_indexes" => true,
      "strict" => true,
      "engine" => nil,
      "options" => pdo_options
    },
    "mariadb" => %{
      "driver" => "mariadb",
      "client" => env.("DB_CLIENT", "cli"),
      "url" => env.("DB_URL", nil),
      "host" => env.("DB_HOST", "127.0.0.1"),
      "port" => env.("DB_PORT", "3306"),
      "database" => env.("DB_DATABASE", "laravex"),
      "username" => env.("DB_USERNAME", "root"),
      "password" => env.("DB_PASSWORD", ""),
      "unix_socket" => env.("DB_SOCKET", ""),
      "charset" => env.("DB_CHARSET", "utf8mb4"),
      "collation" => env.("DB_COLLATION", "utf8mb4_unicode_ci"),
      "prefix" => "",
      "pool" => env.("DB_POOL_SIZE", 5),
      "prefix_indexes" => true,
      "strict" => true,
      "engine" => nil,
      "options" => pdo_options
    },
    "pgsql" => %{
      "driver" => "pgsql",
      "client" => env.("DB_CLIENT", "cli"),
      "url" => env.("DB_URL", nil),
      "host" => env.("DB_HOST", "127.0.0.1"),
      "port" => env.("DB_PORT", "5432"),
      "database" => env.("DB_DATABASE", "laravex"),
      "username" => env.("DB_USERNAME", "root"),
      "password" => env.("DB_PASSWORD", ""),
      "charset" => env.("DB_CHARSET", "utf8"),
      "prefix" => "",
      "pool" => env.("DB_POOL_SIZE", 5),
      "prefix_indexes" => true,
      "search_path" => "public",
      "sslmode" => env.("DB_SSLMODE", "prefer")
    },
    "sqlsrv" => %{
      "driver" => "sqlsrv",
      # TDS only — there is no CLI sqlsrv adapter; ignore DB_CLIENT=cli.
      "client" => "native",
      "url" => env.("DB_URL", nil),
      "host" => env.("DB_HOST", "localhost"),
      "port" => env.("DB_PORT", "1433"),
      "database" => env.("DB_DATABASE", "laravex"),
      "username" => env.("DB_USERNAME", "root"),
      "password" => env.("DB_PASSWORD", ""),
      "charset" => env.("DB_CHARSET", "utf8"),
      "prefix" => "",
      "pool" => env.("DB_POOL_SIZE", 5),
      "prefix_indexes" => true
    }
  },
  "migrations" => %{
    "table" => "migrations",
    "update_date_on_publish" => true
  },
  "redis" => %{
    "client" => env.("REDIS_CLIENT", "phpredis"),
    "options" => %{
      "cluster" => env.("REDIS_CLUSTER", "redis"),
      "prefix" => env.("REDIS_PREFIX", "laravex-database-")
    },
    "default" => %{
      "url" => env.("REDIS_URL", nil),
      "host" => env.("REDIS_HOST", "127.0.0.1"),
      "username" => env.("REDIS_USERNAME", nil),
      "password" => env.("REDIS_PASSWORD", nil),
      "port" => env.("REDIS_PORT", "6379"),
      "database" => env.("REDIS_DB", "0")
    },
    "cache" => %{
      "url" => env.("REDIS_URL", nil),
      "host" => env.("REDIS_HOST", "127.0.0.1"),
      "username" => env.("REDIS_USERNAME", nil),
      "password" => env.("REDIS_PASSWORD", nil),
      "port" => env.("REDIS_PORT", "6379"),
      "database" => env.("REDIS_CACHE_DB", "1")
    }
  }
}
