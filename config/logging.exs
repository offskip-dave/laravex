env = &Laravex.Env.get/2
base = File.cwd!()
log_path = Path.join(base, "storage/logs/laravex.log")

# Available drivers: "single", "daily", "monthly", "slack", "syslog",
#                    "errorlog", "stderr", "null", "stack"

%{
  "default" => env.("LOG_CHANNEL", "stack"),
  "deprecations" => %{
    "channel" => env.("LOG_DEPRECATIONS_CHANNEL", "null"),
    "trace" => env.("LOG_DEPRECATIONS_TRACE", false)
  },
  "channels" => %{
    "stack" => %{
      "driver" => "stack",
      "channels" => String.split(to_string(env.("LOG_STACK", "single")), ",", trim: true),
      "ignore_exceptions" => false
    },
    "single" => %{
      "driver" => "single",
      "path" => log_path,
      "level" => env.("LOG_LEVEL", "debug"),
      "replace_placeholders" => true
    },
    "daily" => %{
      "driver" => "daily",
      "path" => log_path,
      "level" => env.("LOG_LEVEL", "debug"),
      "max_files" => env.("LOG_DAILY_DAYS", 14),
      "replace_placeholders" => true
    },
    "monthly" => %{
      "driver" => "monthly",
      "path" => log_path,
      "level" => env.("LOG_LEVEL", "debug"),
      "max_files" => 3,
      "replace_placeholders" => true
    },
    "slack" => %{
      "driver" => "slack",
      "url" => env.("LOG_SLACK_WEBHOOK_URL", nil),
      "username" => env.("LOG_SLACK_USERNAME", env.("APP_NAME", "Laravex")),
      "emoji" => env.("LOG_SLACK_EMOJI", ":boom:"),
      "level" => env.("LOG_LEVEL", "critical"),
      "replace_placeholders" => true
    },
    "stderr" => %{
      "driver" => "stderr",
      "level" => env.("LOG_LEVEL", "debug"),
      "replace_placeholders" => true
    },
    "syslog" => %{
      "driver" => "syslog",
      "level" => env.("LOG_LEVEL", "debug"),
      "facility" => env.("LOG_SYSLOG_FACILITY", "user"),
      "replace_placeholders" => true
    },
    "errorlog" => %{
      "driver" => "errorlog",
      "level" => env.("LOG_LEVEL", "debug"),
      "replace_placeholders" => true
    },
    "null" => %{
      "driver" => "null"
    }
  }
}
