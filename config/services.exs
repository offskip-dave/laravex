env = &Laravex.Env.get/2

%{
  "postmark" => %{
    "key" => env.("POSTMARK_API_KEY", nil)
  },
  "resend" => %{
    "key" => env.("RESEND_API_KEY", nil)
  },
  "ses" => %{
    "key" => env.("AWS_ACCESS_KEY_ID", nil),
    "secret" => env.("AWS_SECRET_ACCESS_KEY", nil),
    "region" => env.("AWS_DEFAULT_REGION", "us-east-1")
  },
  "slack" => %{
    "notifications" => %{
      "bot_user_oauth_token" => env.("SLACK_BOT_USER_OAUTH_TOKEN", nil),
      "channel" => env.("SLACK_BOT_USER_DEFAULT_CHANNEL", nil)
    }
  }
}
