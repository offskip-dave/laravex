# Port of public/index.php — HTTP entry that boots the app and handles one request from stdin,
# or starts the long-running server when invoked with --serve.

base = Path.expand("..", __DIR__)
File.cd!(base)

Application.ensure_all_started(:laravex)
Laravex.Foundation.Server.boot!()

case System.argv() do
  ["--serve" | _] ->
    port = Application.get_env(:laravex, :http_port, 8000)
    {:ok, _pid, actual} = Laravex.Http.Server.start_link(port: port)
    IO.puts("Laravex serving on http://127.0.0.1:#{actual}")
    Process.sleep(:infinity)

  _ ->
    # Demo single-request path used by tooling: GET /
    request = Laravex.Http.Request.capture("GET", "/")
    response = Laravex.Foundation.Application.handle_request(request)
    IO.puts(response.body)
end
