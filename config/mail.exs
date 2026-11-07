env = &Laravex.Env.get/2

%{
  "default" => env.("MAIL_MAILER", "log"),
  "mailers" => %{
    "smtp" => %{
      "transport" => "smtp",
      "scheme" => env.("MAIL_SCHEME", nil),
      "url" => env.("MAIL_URL", nil),
      "host" => env.("MAIL_HOST", "127.0.0.1"),
      "port" => env.("MAIL_PORT", 2525),
      "username" => env.("MAIL_USERNAME", nil),
      "password" => env.("MAIL_PASSWORD", nil),
      "timeout" => nil,
      "local_domain" => env.("MAIL_EHLO_DOMAIN", "localhost")
    },
    "ses" => %{"transport" => "ses"},
    "postmark" => %{"transport" => "postmark"},
    "resend" => %{"transport" => "resend"},
    "sendmail" => %{
      "transport" => "sendmail",
      "path" => env.("MAIL_SENDMAIL_PATH", "/usr/sbin/sendmail -bs -i")
    },
    "log" => %{
      "transport" => "log",
      "channel" => env.("MAIL_LOG_CHANNEL", nil)
    },
    "array" => %{"transport" => "array"},
    "failover" => %{
      "transport" => "failover",
      "mailers" => ["smtp", "log"],
      "retry_after" => 60
    },
    "roundrobin" => %{
      "transport" => "roundrobin",
      "mailers" => ["ses", "postmark"],
      "retry_after" => 60
    }
  },
  "from" => %{
    "address" => env.("MAIL_FROM_ADDRESS", "hello@example.com"),
    "name" => env.("MAIL_FROM_NAME", "Example")
  }
}
