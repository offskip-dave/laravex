env = &Laravex.Env.get/2
base = File.cwd!()

%{
  "default" => env.("DB_CONNECTION", "sqlite"),
  "connections" => %{
    "sqlite" => %{
      "driver" => "sqlite",
      "url" => env.("DB_URL", nil),
      "database" => env.("DB_DATABASE", Path.join(base, "database/database.sqlite")),
      "prefix" => "",
      "foreign_key_constraints" => env.("DB_FOREIGN_KEYS", true),
      "busy_timeout" => nil,
      "journal_mode" => nil,
      "synchronous" => nil,
      "transaction_mode" => "DEFERRED"
    },
    "mysql" => %{
      "driver" => "mysql",
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
      "prefix_indexes" => true,
      "strict" => true,
      "engine" => nil,
      "options" => %{}
    },
    "mariadb" => %{
      "driver" => "mariadb",
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
      "prefix_indexes" => true,
      "strict" => true,
      "engine" => nil,
      "options" => %{}
    },
    "pgsql" => %{
      "driver" => "pgsql",
      "url" => env.("DB_URL", nil),
      "host" => env.("DB_HOST", "127.0.0.1"),
      "port" => env.("DB_PORT", "5432"),
      "database" => env.("DB_DATABASE", "laravex"),
      "username" => env.("DB_USERNAME", "root"),
      "password" => env.("DB_PASSWORD", ""),
      "charset" => env.("DB_CHARSET", "utf8"),
      "prefix" => "",
      "prefix_indexes" => true,
      "search_path" => "public",
      "sslmode" => env.("DB_SSLMODE", "prefer")
    },
    "sqlsrv" => %{
      "driver" => "sqlsrv",
      "url" => env.("DB_URL", nil),
      "host" => env.("DB_HOST", "localhost"),
      "port" => env.("DB_PORT", "1433"),
      "database" => env.("DB_DATABASE", "laravex"),
      "username" => env.("DB_USERNAME", "root"),
      "password" => env.("DB_PASSWORD", ""),
      "charset" => env.("DB_CHARSET", "utf8"),
      "prefix" => "",
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
