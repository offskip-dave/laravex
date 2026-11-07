env = &Laravex.Env.get/2
base = File.cwd!()

%{
  "default" => env.("FILESYSTEM_DISK", "local"),
  "disks" => %{
    "local" => %{
      "driver" => "local",
      "root" => Path.join(base, "storage/app/private"),
      "serve" => true,
      "throw" => false,
      "report" => false
    },
    "public" => %{
      "driver" => "local",
      "root" => Path.join(base, "storage/app/public"),
      "url" => String.trim_trailing(env.("APP_URL", "http://localhost"), "/") <> "/storage",
      "visibility" => "public",
      "throw" => false,
      "report" => false
    },
    "s3" => %{
      "driver" => "s3",
      "key" => env.("AWS_ACCESS_KEY_ID", nil),
      "secret" => env.("AWS_SECRET_ACCESS_KEY", nil),
      "region" => env.("AWS_DEFAULT_REGION", nil),
      "bucket" => env.("AWS_BUCKET", nil),
      "url" => env.("AWS_URL", nil),
      "endpoint" => env.("AWS_ENDPOINT", nil),
      "use_path_style_endpoint" => env.("AWS_USE_PATH_STYLE_ENDPOINT", false),
      "throw" => false,
      "report" => false
    }
  },
  "links" => %{
    Path.join(base, "public/storage") => Path.join(base, "storage/app/public")
  }
}
