%{
  "default" => Laravex.Env.get("BROADCAST_CONNECTION", "log"),
  "connections" => %{
    "log" => %{"driver" => "log"},
    "null" => %{"driver" => "null"},
    "reverb" => %{"driver" => "reverb"},
    "pusher" => %{"driver" => "pusher"},
    "ably" => %{"driver" => "ably"}
  }
}
