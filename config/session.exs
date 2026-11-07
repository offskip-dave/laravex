env = &Laravex.Env.get/2
base = File.cwd!()

%{
  "driver" => env.("SESSION_DRIVER", "database"),
  "lifetime" => env.("SESSION_LIFETIME", 120),
  "expire_on_close" => env.("SESSION_EXPIRE_ON_CLOSE", false),
  "encrypt" => env.("SESSION_ENCRYPT", false),
  "files" => Path.join(base, "storage/framework/sessions"),
  "connection" => env.("SESSION_CONNECTION", nil),
  "table" => env.("SESSION_TABLE", "sessions"),
  "store" => env.("SESSION_STORE", nil),
  "lottery" => [2, 100],
  "cookie" => env.("SESSION_COOKIE", "laravex-session"),
  "path" => env.("SESSION_PATH", "/"),
  "domain" => env.("SESSION_DOMAIN", nil),
  "secure" => env.("SESSION_SECURE_COOKIE", nil),
  "http_only" => env.("SESSION_HTTP_ONLY", true),
  "same_site" => env.("SESSION_SAME_SITE", "lax"),
  "partitioned" => env.("SESSION_PARTITIONED_COOKIE", false),
  "serialization" => "php"
}
