defmodule Laravex.Console.Kernel do
  @moduledoc "Artisan command dispatcher."

  @commands %{
    "inspire" => {&__MODULE__.cmd_inspire/1, "Display an inspiring quote"},
    "list" => {&__MODULE__.cmd_list/1, "List commands"},
    "serve" => {&__MODULE__.cmd_serve/1, "Serve the application"},
    "migrate" => {&__MODULE__.cmd_migrate/1, "Run migrations"},
    "migrate:rollback" => {&__MODULE__.cmd_rollback/1, "Rollback migrations"},
    "migrate:refresh" => {&__MODULE__.cmd_refresh/1, "Refresh migrations"},
    "migrate:fresh" => {&__MODULE__.cmd_fresh/1, "Drop all tables and re-run migrations"},
    "migrate:status" => {&__MODULE__.cmd_status/1, "Show migration status"},
    "db:seed" => {&__MODULE__.cmd_seed/1, "Seed the database"},
    "db:wipe" => {&__MODULE__.cmd_wipe/1, "Drop all tables"},
    "route:list" => {&__MODULE__.cmd_routes/1, "List routes"},
    "config:cache" => {&__MODULE__.cmd_config_cache/1, "Cache configuration"},
    "config:clear" => {&__MODULE__.cmd_config_clear/1, "Clear configuration cache"},
    "view:cache" => {&__MODULE__.cmd_view_cache/1, "Cache views"},
    "view:clear" => {&__MODULE__.cmd_view_clear/1, "Clear compiled views"},
    "queue:work" => {&__MODULE__.cmd_queue_work/1, "Process queue jobs"},
    "schedule:run" => {&__MODULE__.cmd_schedule/1, "Run due scheduled tasks"},
    "tinker" => {&__MODULE__.cmd_tinker/1, "Interact with the application"},
    "storage:link" => {&__MODULE__.cmd_storage_link/1, "Link public storage"},
    "down" => {&__MODULE__.cmd_down/1, "Put the application into maintenance mode"},
    "up" => {&__MODULE__.cmd_up/1, "Bring the application out of maintenance mode"},
    "about" => {&__MODULE__.cmd_about/1, "Display basic application information"},
    "test" => {&__MODULE__.cmd_test/1, "Run the test suite"},
    "make:model" => {&__MODULE__.cmd_make_model/1, "Create a new model class"},
    "make:controller" => {&__MODULE__.cmd_make_controller/1, "Create a controller"},
    "make:migration" => {&__MODULE__.cmd_make_migration/1, "Create a migration"},
    "make:job" => {&__MODULE__.cmd_make_job/1, "Create a job"},
    "make:event" => {&__MODULE__.cmd_make_event/1, "Create an event"},
    "make:listener" => {&__MODULE__.cmd_make_listener/1, "Create a listener"},
    "make:mail" => {&__MODULE__.cmd_make_mail/1, "Create a mailable"},
    "make:notification" => {&__MODULE__.cmd_make_notification/1, "Create a notification"},
    "make:policy" => {&__MODULE__.cmd_make_policy/1, "Create a policy"},
    "make:request" => {&__MODULE__.cmd_make_request/1, "Create a form request"},
    "make:rule" => {&__MODULE__.cmd_make_rule/1, "Create a validation rule"},
    "make:provider" => {&__MODULE__.cmd_make_provider/1, "Create a provider"},
    "make:command" => {&__MODULE__.cmd_make_command/1, "Create a command"},
    "make:middleware" => {&__MODULE__.cmd_make_middleware/1, "Create middleware"},
    "make:resource" => {&__MODULE__.cmd_make_resource/1, "Create an API resource"},
    "make:factory" => {&__MODULE__.cmd_make_factory/1, "Create a factory"},
    "make:seeder" => {&__MODULE__.cmd_make_seeder/1, "Create a seeder"},
    "install:api" => {&__MODULE__.cmd_install_api/1, "Install API routes and tokens"},
    "install:broadcasting" => {&__MODULE__.cmd_install_broadcasting/1, "Install broadcasting"},
    "install:starter-kit" => {&__MODULE__.cmd_install_starter/1, "Install auth starter kit"}
  }

  def main(argv) do
    Application.ensure_all_started(:laravex)
    Laravex.Foundation.Server.boot!()

    case argv do
      [] ->
        cmd_list([])

      ["list" | _] ->
        cmd_list([])

      [command | args] ->
        case Map.get(@commands, command) do
          {fun, _} ->
            fun.(args)

          nil ->
            case Laravex.Console.Router.dispatch(command, args) do
              :ok -> :ok
              :not_found ->
                IO.puts(:stderr, "Command not found: #{command}")
                System.halt(1)
            end
        end
    end
  end

  def commands, do: @commands

  def cmd_inspire(_), do: IO.puts(Laravex.Support.Inspiring.quote_text())

  def cmd_list(_) do
    IO.puts("Laravex Artisan\n")

    @commands
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.each(fn {name, {_, desc}} ->
      IO.puts("  #{String.pad_trailing(name, 24)} #{desc}")
    end)
  end

  def cmd_serve(args) do
    port =
      case args do
        ["--port=" <> p | _] -> String.to_integer(p)
        [p | _] -> String.to_integer(p)
        _ -> Application.get_env(:laravex, :http_port, 8000)
      end

    {:ok, _pid, actual} = Laravex.Http.Server.start_link(port: port)
    IO.puts("Laravex development server started: http://127.0.0.1:#{actual}")
    Process.sleep(:infinity)
  end

  def cmd_migrate(_), do: (Laravex.Database.Migrator.migrate(); :ok)
  def cmd_rollback(_), do: (Laravex.Database.Migrator.rollback(); :ok)
  def cmd_refresh(_), do: (Laravex.Database.Migrator.refresh(); :ok)
  def cmd_fresh(_), do: (Laravex.Database.Migrator.fresh(); IO.puts("Dropped all tables and re-ran migrations."); :ok)
  def cmd_wipe(_), do: (Laravex.Database.Migrator.wipe(); IO.puts("Dropped all tables."); :ok)

  def cmd_status(_) do
    Laravex.Database.Migrator.status()
    |> Enum.each(fn %{migration: m, status: s} -> IO.puts("#{String.pad_trailing(s, 10)} #{m}") end)
  end

  def cmd_seed(_), do: (Database.Seeders.DatabaseSeeder.run(); IO.puts("Database seeded."); :ok)

  def cmd_routes(_) do
    Laravex.Routing.Router.routes()
    |> Enum.each(fn r ->
      IO.puts("#{String.pad_trailing(r.method, 7)} #{String.pad_trailing(r.uri, 40)} #{r.name}")
    end)
  end

  def cmd_config_cache(_) do
    Laravex.Config.Repository.cache!()
    IO.puts("Configuration cached successfully.")
  end

  def cmd_config_clear(_) do
    Laravex.Config.Repository.clear_cache!()
    IO.puts("Configuration cache cleared.")
  end

  def cmd_view_cache(_) do
    n = Laravex.View.Cache.warm()
    IO.puts("Blade templates cached (#{n} views).")
  end

  def cmd_view_clear(_) do
    Laravex.View.Cache.clear()
    IO.puts("Compiled views cleared.")
  end

  def cmd_queue_work(args) do
    once = "--once" in args
    Laravex.Queue.Worker.work(once: once)
  end

  def cmd_schedule(_), do: Laravex.Console.Schedule.run()

  def cmd_tinker(_) do
    IO.puts("Laravex Tinker (exit/quit to leave)")
    tinker_loop([])
  end

  def cmd_storage_link(_), do: (Laravex.Filesystem.Storage.link(); IO.puts("The links have been created."))

  def cmd_down(args) do
    opts = parse_down_opts(args)
    Laravex.Foundation.Maintenance.down(opts)
    IO.puts("Application is now in maintenance mode.")
  end

  def cmd_up(_) do
    Laravex.Foundation.Maintenance.up()
    IO.puts("Application is now live.")
  end

  def cmd_about(_) do
    name = Laravex.Config.Repository.get("app.name", "Laravex")
    env = Laravex.Config.Repository.get("app.env", "local")
    debug = Laravex.Config.Repository.get("app.debug", false)
    maintenance = Laravex.Foundation.Maintenance.enabled?()

    IO.puts("""
    #{name}
      Environment ................ #{env}
      Debug ...................... #{debug}
      Maintenance ................ #{maintenance}
      Elixir ..................... #{System.version()}
      OTP ........................ #{:erlang.system_info(:otp_release)}
    """)
  end

  def cmd_test(_), do: Mix.Task.run("test")

  def cmd_make_model([name | rest]) do
    Laravex.Generators.make_model(name, rest)
  end

  def cmd_make_model(_), do: usage("make:model", "Name")

  def cmd_make_controller([name | _]), do: Laravex.Generators.make_controller(name)
  def cmd_make_controller(_), do: usage("make:controller", "Name")
  def cmd_make_migration([name | _]), do: Laravex.Generators.make_migration(name)
  def cmd_make_migration(_), do: usage("make:migration", "name")
  def cmd_make_job([name | _]), do: Laravex.Generators.stub("Jobs", name, job_stub(name))
  def cmd_make_job(_), do: usage("make:job", "Name")
  def cmd_make_event([name | _]), do: Laravex.Generators.make_event(name)
  def cmd_make_event(_), do: usage("make:event", "Name")

  def cmd_make_listener([name | rest]) do
    event =
      Enum.find_value(rest, fn
        "--event=" <> e -> e
        _ -> nil
      end)

    Laravex.Generators.make_listener(name, event: event)
  end

  def cmd_make_listener(_), do: usage("make:listener", "Name [--event=Event]")
  def cmd_make_mail([name | _]), do: Laravex.Generators.stub("Mail", name, mail_stub(name))
  def cmd_make_mail(_), do: usage("make:mail", "Name")
  def cmd_make_notification([name | _]), do: Laravex.Generators.stub("Notifications", name, notification_stub(name))
  def cmd_make_notification(_), do: usage("make:notification", "Name")
  def cmd_make_policy([name | _]), do: Laravex.Generators.make_policy(name)
  def cmd_make_policy(_), do: usage("make:policy", "Name")
  def cmd_make_request([name | _]), do: Laravex.Generators.stub("Http/Requests", name, request_stub(name))
  def cmd_make_request(_), do: usage("make:request", "Name")
  def cmd_make_rule([name | _]), do: Laravex.Generators.stub("Rules", name, rule_stub(name))
  def cmd_make_rule(_), do: usage("make:rule", "Name")
  def cmd_make_provider([name | _]), do: Laravex.Generators.stub("Providers", name, provider_stub(name))
  def cmd_make_provider(_), do: usage("make:provider", "Name")
  def cmd_make_command([name | _]), do: Laravex.Generators.make_command(name)
  def cmd_make_command(_), do: usage("make:command", "Name")
  def cmd_make_middleware([name | _]), do: Laravex.Generators.make_middleware(name)
  def cmd_make_middleware(_), do: usage("make:middleware", "Name")
  def cmd_make_resource([name | _]), do: Laravex.Generators.make_resource(name)
  def cmd_make_resource(_), do: usage("make:resource", "Name")
  def cmd_make_factory([name | _]), do: Laravex.Generators.make_factory(name)
  def cmd_make_factory(_), do: usage("make:factory", "Name")
  def cmd_make_seeder([name | _]), do: Laravex.Generators.make_seeder(name)
  def cmd_make_seeder(_), do: usage("make:seeder", "Name")

  def cmd_install_api(_), do: Laravex.Install.api()
  def cmd_install_broadcasting(_), do: Laravex.Install.broadcasting()
  def cmd_install_starter(_), do: Laravex.Install.starter_kit()

  defp usage(cmd, arg), do: IO.puts("Usage: artisan #{cmd} #{arg}")

  defp parse_down_opts(args) do
    Enum.reduce(args, [], fn
      "--message=" <> msg, acc -> Keyword.put(acc, :message, msg)
      "--retry=" <> n, acc -> Keyword.put(acc, :retry, String.to_integer(n))
      "--secret=" <> s, acc -> Keyword.put(acc, :secret, s)
      _, acc -> acc
    end)
  end

  defp tinker_loop(bindings) do
    case IO.gets(">>> ") do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      line ->
        line = String.trim(line)

        cond do
          line in ["exit", "quit"] ->
            :ok

          line == "" ->
            tinker_loop(bindings)

          true ->
            try do
              {result, new_bindings} = Code.eval_string(line, bindings)
              IO.inspect(result)
              tinker_loop(Keyword.merge(bindings, new_bindings))
            rescue
              e ->
                IO.puts(:stderr, Exception.message(e))
                tinker_loop(bindings)
            end
        end
    end
  end

  defp job_stub(name), do: """
  defmodule App.Jobs.#{name} do
    @moduledoc \"\"\"
    Queued job. Use `queue: false` for sync-only jobs.

        App.Jobs.#{name}.dispatch([arg])
        App.Jobs.#{name}.dispatch_sync([arg])
        App.Jobs.#{name}.dispatch([arg], connection: "deferred", delay: 10)
    \"\"\"

    use Laravex.Queue.Job, queue: true

    def handle(args) do
      {:ok, args}
    end
  end
  """

  defp mail_stub(name), do: """
  defmodule App.Mail.#{name} do
    use Laravex.Mail.Mailable
    def to, do: "user@example.com"
    def subject, do: "#{name}"
    def content, do: "Hello"
  end
  """

  defp notification_stub(name), do: """
  defmodule App.Notifications.#{name} do
    def via(_), do: [:mail, :log]
    def to_mail(user), do: %{to: user.email, subject: "#{name}", body: "Hi"}
  end
  """

  defp request_stub(name), do: """
  defmodule App.Http.Requests.#{name} do
    use Laravex.Http.FormRequest
    def rules, do: %{"name" => "required|string"}
  end
  """

  defp rule_stub(name), do: """
  defmodule App.Rules.#{name} do
    def passes?(_attribute, _value), do: true
    def message, do: "validation failed"
  end
  """

  defp provider_stub(name), do: """
  defmodule App.Providers.#{name} do
    def register, do: :ok
    def boot, do: :ok
  end
  """

end
