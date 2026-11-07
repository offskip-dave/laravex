env = &Laravex.Env.get/2

defaults = [
  "localhost",
  "localhost:3000",
  "127.0.0.1",
  "127.0.0.1:8000",
  "::1"
]

extra =
  case env.("SANCTUM_STATEFUL_DOMAINS", nil) do
    nil -> []
    raw -> String.split(raw, ",", trim: true)
  end

%{
  "stateful" => Enum.uniq(defaults ++ extra)
}
