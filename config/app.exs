# Laravel-style config/app.php — loaded by Laravex.Config.Repository
env = &Laravex.Env.get/2

%{
  "name" => env.("APP_NAME", "Laravex"),
  "env" => env.("APP_ENV", "production"),
  "debug" => env.("APP_DEBUG", false),
  "url" => env.("APP_URL", "http://localhost"),
  "timezone" => "UTC",
  "locale" => env.("APP_LOCALE", "en"),
  "fallback_locale" => env.("APP_FALLBACK_LOCALE", "en"),
  "faker_locale" => env.("APP_FAKER_LOCALE", "en_US"),
  "cipher" => "AES-256-CBC",
  "key" => env.("APP_KEY", nil),
  "previous_keys" =>
    (env.("APP_PREVIOUS_KEYS", "") || "")
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.reject(&(&1 == "")),
  "maintenance" => %{
    "driver" => env.("APP_MAINTENANCE_DRIVER", "file"),
    "store" => env.("APP_MAINTENANCE_STORE", "database")
  }
}
