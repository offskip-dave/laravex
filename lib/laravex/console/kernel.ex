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
    "db:show" => {&__MODULE__.cmd_db_show/1, "Display information about the given database"},
    "model:show" => {&__MODULE__.cmd_model_show/1, "Show information about an Eloquex model"},
    "route:list" => {&__MODULE__.cmd_routes/1, "List routes"},
    "config:cache" => {&__MODULE__.cmd_config_cache/1, "Cache configuration"},
    "config:clear" => {&__MODULE__.cmd_config_clear/1, "Clear configuration cache"},
    "route:cache" => {&__MODULE__.cmd_route_cache/1, "Cache the route collection"},
    "route:clear" => {&__MODULE__.cmd_route_clear/1, "Remove the route cache file"},
    "route:match" => {&__MODULE__.cmd_route_match/1, "Match a route for method and URI"},
    "cache:clear" => {&__MODULE__.cmd_cache_clear/1, "Flush the application cache"},
    "cache:forget" => {&__MODULE__.cmd_cache_forget/1, "Remove an item from the cache"},
    "view:cache" => {&__MODULE__.cmd_view_cache/1, "Cache views"},
    "view:clear" => {&__MODULE__.cmd_view_clear/1, "Clear compiled views"},
    "optimize" => {&__MODULE__.cmd_optimize/1, "Cache framework bootstrap files"},
    "optimize:clear" => {&__MODULE__.cmd_optimize_clear/1, "Remove cached bootstrap files"},
    "queue:work" => {&__MODULE__.cmd_queue_work/1, "Process queue jobs"},
    "queue:failed" => {&__MODULE__.cmd_queue_failed/1, "List all of the failed queue jobs"},
    "queue:retry" => {&__MODULE__.cmd_queue_retry/1, "Retry a failed queue job"},
    "queue:forget" => {&__MODULE__.cmd_queue_forget/1, "Delete a failed queue job"},
    "queue:flush" => {&__MODULE__.cmd_queue_flush/1, "Flush all of the failed queue jobs"},
    "queue:batches" => {&__MODULE__.cmd_queue_batches/1, "List the job batches"},
    "queue:batch" => {&__MODULE__.cmd_queue_batch/1, "Show or cancel a job batch"},
    "sanctum:prune-expired" => {&__MODULE__.cmd_prune_tokens/1, "Prune expired API tokens"},
    "schedule:run" => {&__MODULE__.cmd_schedule/1, "Run due scheduled tasks"},
    "schedule:list" => {&__MODULE__.cmd_schedule_list/1, "List all scheduled tasks"},
    "event:list" => {&__MODULE__.cmd_event_list/1, "List registered events and listeners"},
    "event:cache" => {&__MODULE__.cmd_event_cache/1, "Cache the event → listener map"},
    "event:clear" => {&__MODULE__.cmd_event_clear/1, "Clear the cached events file"},
    "tinker" => {&__MODULE__.cmd_tinker/1, "Interact with the application"},
    "storage:link" => {&__MODULE__.cmd_storage_link/1, "Link public storage"},
    "down" => {&__MODULE__.cmd_down/1, "Put the application into maintenance mode"},
    "up" => {&__MODULE__.cmd_up/1, "Bring the application out of maintenance mode"},
    "about" => {&__MODULE__.cmd_about/1, "Display basic application information"},
    "env" => {&__MODULE__.cmd_env/1, "Display the current framework environment"},
    "key:generate" => {&__MODULE__.cmd_key_generate/1, "Set the application key"},
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
    "make:view" => {&__MODULE__.cmd_make_view/1, "Create a Blade view"},
    "make:test" => {&__MODULE__.cmd_make_test/1, "Create a test class"},
    "make:observer" => {&__MODULE__.cmd_make_observer/1, "Create a model observer"},
    "make:enum" => {&__MODULE__.cmd_make_enum/1, "Create an enum"},
    "install:api" => {&__MODULE__.cmd_install_api/1, "Install API routes and tokens"},
    "install:broadcasting" => {&__MODULE__.cmd_install_broadcasting/1, "Install broadcasting"},
    "install:starter-kit" => {&__MODULE__.cmd_install_starter/1, "Install auth starter kit"}
  }

  def main(argv) do
    _ = Application.ensure_all_started(:laravex)
    _ = Laravex.Foundation.Server.boot!()

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

  def cmd_seed(_) do
    _ = Database.Seeders.DatabaseSeeder.run()
    IO.puts("Database seeded.")
    :ok
  end

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

  def cmd_route_cache(_) do
    Laravex.Routing.RouteCache.clear!()
    Laravex.Routing.Router.reset()

    _ =
      case Laravex.Foundation.Application.instance() do
        %{base_path: base} = instance ->
          app = %Laravex.Foundation.Application{
            base_path: base,
            web_routes: Path.join(base, "routes/web.ex"),
            health: Map.get(instance, :health) || "/up"
          }

          Laravex.Foundation.Application.register_http_routes(app)

        _ ->
          Laravex.Foundation.Server.boot!()
      end

    Laravex.Routing.RouteCache.cache!()
    IO.puts("Routes cached successfully.")
  end

  def cmd_route_clear(_) do
    Laravex.Routing.RouteCache.clear!()
    IO.puts("Route cache cleared.")
  end

  def cmd_route_match([method, uri | _]) do
    request = Laravex.Http.Request.capture(method, uri)

    case Laravex.Routing.Router.match(request) do
      :error ->
        IO.puts("No matching route for #{String.upcase(method)} #{uri}")

      {:ok, req, handler, opts} ->
        name = Keyword.get(opts, :name, "—")
        IO.puts("MATCH  #{String.upcase(method)} #{uri}")
        IO.puts("  name:   #{name}")
        IO.puts("  params: #{inspect(req.route_params)}")
        IO.puts("  action: #{inspect(handler)}")
    end

    :ok
  end

  def cmd_route_match(_), do: usage("route:match", "{method} {uri}")

  def cmd_cache_clear(_) do
    Laravex.Cache.Manager.flush()
    IO.puts("Application cache cleared.")
    :ok
  end

  def cmd_cache_forget([key | _]) do
    Laravex.Cache.Manager.forget(key)
    IO.puts("Removed cache key #{key}")
    :ok
  end

  def cmd_cache_forget(_), do: usage("cache:forget", "{key}")

  def cmd_view_cache(_) do
    n = Laravex.View.Cache.warm()
    IO.puts("Blade templates cached (#{n} views).")
  end

  def cmd_view_clear(_) do
    Laravex.View.Cache.clear()
    IO.puts("Compiled views cleared.")
  end

  def cmd_optimize(_) do
    cmd_config_cache([])
    cmd_route_cache([])
    cmd_event_cache([])
    cmd_view_cache([])
    IO.puts("Files cached successfully.")
  end

  def cmd_optimize_clear(_) do
    cmd_config_clear([])
    cmd_route_clear([])
    cmd_event_clear([])
    cmd_view_clear([])
    IO.puts("Cached bootstrap files cleared successfully.")
  end

  def cmd_queue_work(args) do
    once = "--once" in args
    Laravex.Queue.Worker.work(once: once)
  end

  def cmd_queue_failed(_) do
    jobs = Laravex.Queue.Worker.failed_jobs()

    if jobs == [] do
      IO.puts("No failed jobs!")
    else
      IO.puts(
        String.pad_trailing("ID", 6) <>
          String.pad_trailing("UUID", 20) <>
          String.pad_trailing("Queue", 12) <> "Failed At"
      )

      Enum.each(jobs, fn job ->
        IO.puts(
          String.pad_trailing(to_string(job["id"]), 6) <>
            String.pad_trailing(to_string(job["uuid"]), 20) <>
            String.pad_trailing(to_string(job["queue"]), 12) <>
            to_string(job["failed_at"])
        )
      end)
    end
  end

  def cmd_queue_retry([id | _]) do
    case Laravex.Queue.Worker.retry_failed(id) do
      {:ok, _} -> IO.puts("The failed job [#{id}] has been pushed back onto the queue.")
      {:error, :not_found} -> IO.puts(:stderr, "No failed job matches [#{id}].")
      {:error, :bad_payload} -> IO.puts(:stderr, "Unable to decode failed job payload.")
    end
  end

  def cmd_queue_retry(_), do: IO.puts("Usage: artisan queue:retry {id|uuid}")

  def cmd_queue_forget([id | _]) do
    case Laravex.Queue.Worker.forget_failed(id) do
      :ok -> IO.puts("Failed job deleted successfully.")
      _ -> IO.puts(:stderr, "No failed job matches [#{id}].")
    end
  end

  def cmd_queue_forget(_), do: IO.puts("Usage: artisan queue:forget {id|uuid}")

  def cmd_queue_flush(_) do
    Laravex.Queue.Worker.flush_failed()
    IO.puts("All failed jobs deleted successfully.")
  end

  def cmd_queue_batches(_) do
    batches = Laravex.Bus.list_batches()

    if batches == [] do
      IO.puts("No job batches found.")
    else
      IO.puts(
        String.pad_trailing("ID", 38) <>
          String.pad_trailing("Name", 18) <>
          String.pad_trailing("Total", 8) <>
          String.pad_trailing("Pending", 10) <>
          String.pad_trailing("Failed", 8) <> "Cancelled"
      )

      Enum.each(batches, fn b ->
        IO.puts(
          String.pad_trailing(to_string(b.id), 38) <>
            String.pad_trailing(to_string(b.name || ""), 18) <>
            String.pad_trailing(to_string(b.total_jobs), 8) <>
            String.pad_trailing(to_string(b.pending_jobs), 10) <>
            String.pad_trailing(to_string(b.failed_jobs), 8) <>
            to_string(b.cancelled_at || "")
        )
      end)
    end
  end

  def cmd_queue_batch(["cancel", id | _]) do
    case Laravex.Bus.cancel(id) do
      {:ok, batch} -> IO.puts("Batch [#{batch.id}] cancelled.")
      {:error, :not_found} -> IO.puts(:stderr, "No batch matches [#{id}].")
    end
  end

  def cmd_queue_batch([id | _]) do
    case Laravex.Bus.find_batch(id) do
      nil ->
        IO.puts(:stderr, "No batch matches [#{id}].")

      b ->
        IO.puts("ID: #{b.id}")
        IO.puts("Name: #{b.name}")
        IO.puts("Total / Pending / Failed: #{b.total_jobs} / #{b.pending_jobs} / #{b.failed_jobs}")
        IO.puts("Failed job ids: #{inspect(b.failed_job_ids)}")
        IO.puts("Created: #{b.created_at}")
        IO.puts("Finished: #{b.finished_at}")
        IO.puts("Cancelled: #{b.cancelled_at}")
    end
  end

  def cmd_queue_batch(_), do: IO.puts("Usage: artisan queue:batch {id} | queue:batch cancel {id}")

  def cmd_prune_tokens(_) do
    Laravex.Auth.Token.prune_expired()
    IO.puts("Expired API tokens pruned.")
  end

  def cmd_db_show(args) do
    table =
      Enum.find_value(args, fn
        "--table=" <> t -> t
        t -> if String.starts_with?(t, "-"), do: nil, else: t
      end)

    if table do
      info = Laravex.Database.Introspection.table_info(table)
      IO.puts("Table: #{info.name}\n")
      IO.puts(String.pad_trailing("Column", 24) <> String.pad_trailing("Type", 12) <> "Nullable")

      Enum.each(info.columns, fn col ->
        IO.puts(
          String.pad_trailing(to_string(col["name"]), 24) <>
            String.pad_trailing(to_string(col["type"]), 12) <>
            if(col["notnull"] in [0, "0"], do: "yes", else: "no")
        )
      end)
    else
      tables = Laravex.Database.Introspection.tables()
      IO.puts("Database\n")
      Enum.each(tables, fn t -> IO.puts("  #{t}") end)
    end
  end

  def cmd_model_show([name | _]) do
    case Laravex.Database.Introspection.resolve_model(name) do
      nil ->
        IO.puts(:stderr, "Model [#{name}] not found.")

      mod ->
        info = Laravex.Database.Introspection.model_info(mod)
        IO.puts("Model: #{inspect(info.module)}")
        IO.puts("Table: #{info.table || "?"}")
        IO.puts("Soft deletes: #{info.soft_deletes?}")
        IO.puts("Fillable: #{inspect(info.fillable)}")
        IO.puts("Guarded: #{inspect(info.guarded)}")
        IO.puts("Casts: #{inspect(info.casts)}")
        IO.puts("Appends: #{inspect(info.appends)}")
        IO.puts("Relations: #{inspect(info.relations)}")

        if info.columns != [] do
          IO.puts("\nColumns:")

          Enum.each(info.columns, fn col ->
            IO.puts("  #{col["name"]} (#{col["type"]})")
          end)
        end
    end
  end

  def cmd_model_show(_), do: IO.puts("Usage: artisan model:show {Model}")

  def cmd_event_cache(_) do
    Laravex.Events.EventCache.cache!()
    IO.puts("Events cached successfully.")
  end

  def cmd_event_clear(_) do
    Laravex.Events.EventCache.clear!()
    IO.puts("Cached events cleared.")
  end

  def cmd_schedule(_), do: Laravex.Console.Schedule.run()

  def cmd_schedule_list(_) do
    tasks = Laravex.Console.Schedule.all()

    if tasks == [] do
      IO.puts("No scheduled tasks have been defined.")
    else
      IO.puts(String.pad_trailing("Expression", 24) <> "Command / Callback")
      IO.puts(String.duplicate("-", 60))

      Enum.each(tasks, fn task ->
        expr = Map.get(task, :expression) || "?"
        label = describe_schedule_task(task)
        IO.puts(String.pad_trailing(to_string(expr), 24) <> label)
      end)
    end
  end

  def cmd_event_list(_) do
    provider_map = event_provider_listen()
    runtime_map = event_runtime_listeners()
    merged = Map.merge(provider_map, runtime_map, fn _k, a, b -> List.wrap(a) ++ List.wrap(b) end)

    if map_size(merged) == 0 do
      IO.puts("No events have been registered.")
    else
      merged
      |> Enum.sort_by(fn {event, _} -> to_string(event) end)
      |> Enum.each(fn {event, listeners} ->
        IO.puts(inspect(event))

        Enum.each(Enum.uniq(List.wrap(listeners)), fn listener ->
          IO.puts("  ⇂ #{inspect(listener)}")
        end)
      end)
    end
  end

  defp event_provider_listen do
    if Code.ensure_loaded?(App.Providers.EventServiceProvider) and
         function_exported?(App.Providers.EventServiceProvider, :listen, 0) do
      App.Providers.EventServiceProvider.listen()
    else
      %{}
    end
  end

  defp event_runtime_listeners do
    try do
      Laravex.Events.Dispatcher.listeners()
    rescue
      _ -> %{}
    end
  end

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
    key? = present?(Laravex.Config.Repository.get("app.key") || Laravex.Env.get("APP_KEY"))

    IO.puts("""
    #{name}
      Environment ................ #{env}
      Debug ...................... #{debug}
      Maintenance ................ #{maintenance}
      APP_KEY .................... #{if key?, do: "set", else: "missing"}
      Elixir ..................... #{System.version()}
      OTP ........................ #{:erlang.system_info(:otp_release)}
    """)
  end

  def cmd_env(args) do
    only =
      Enum.find_value(args, fn
        "--only=" <> key -> key
        _ -> nil
      end)

    env = Laravex.Env.all()

    env
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.each(fn {k, v} ->
      if is_nil(only) or only == k do
        IO.puts("#{k}=#{redact_env(k, v)}")
      end
    end)

    :ok
  end

  def cmd_key_generate(args) do
    force? = "--force" in args
    existing = Laravex.Env.get("APP_KEY")

    if present?(existing) and not force? do
      IO.puts("APP_KEY already set. Use --force to overwrite.")
    else
      key = "base64:" <> Base.encode64(:crypto.strong_rand_bytes(32))
      Laravex.Env.write!("APP_KEY", key)
      Laravex.Config.Repository.load!(Laravex.Foundation.Application.base_path())
      IO.puts("Application key set successfully.")
    end
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
  def cmd_make_job([name | _]), do: Laravex.Generators.make_job(name)
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
  def cmd_make_mail([name | _]), do: Laravex.Generators.make_mail(name)
  def cmd_make_mail(_), do: usage("make:mail", "Name")
  def cmd_make_notification([name | _]), do: Laravex.Generators.make_notification(name)
  def cmd_make_notification(_), do: usage("make:notification", "Name")
  def cmd_make_policy([name | _]), do: Laravex.Generators.make_policy(name)
  def cmd_make_policy(_), do: usage("make:policy", "Name")
  def cmd_make_request([name | _]), do: Laravex.Generators.make_request(name)
  def cmd_make_request(_), do: usage("make:request", "Name")
  def cmd_make_rule([name | _]), do: Laravex.Generators.make_rule(name)
  def cmd_make_rule(_), do: usage("make:rule", "Name")
  def cmd_make_provider([name | _]), do: Laravex.Generators.make_provider(name)
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

  def cmd_make_view([name | _]), do: Laravex.Generators.make_view(name)
  def cmd_make_view(_), do: usage("make:view", "name")

  def cmd_make_test([name | rest]) do
    unit? = "--unit" in rest or "-u" in rest
    Laravex.Generators.make_test(name, unit: unit?)
  end

  def cmd_make_test(_), do: usage("make:test", "Name [--unit]")

  def cmd_make_observer([name | _]), do: Laravex.Generators.make_observer(name)
  def cmd_make_observer(_), do: usage("make:observer", "Name")

  def cmd_make_enum([name | _]), do: Laravex.Generators.make_enum(name)
  def cmd_make_enum(_), do: usage("make:enum", "Name")

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

  defp present?(v), do: not (is_nil(v) or v == "")

  defp redact_env(key, value) do
    sensitive = ~w(KEY SECRET PASSWORD TOKEN PRIVATE)
    upper = String.upcase(to_string(key))

    if Enum.any?(sensitive, &String.contains?(upper, &1)) and present?(value) do
      "********"
    else
      inspect(value)
    end
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

  defp describe_schedule_task(%{opts: opts} = task) do
    cond do
      is_binary(Keyword.get(opts || [], :description)) ->
        Keyword.get(opts, :description)

      is_binary(Keyword.get(opts || [], :command)) ->
        Keyword.get(opts, :command)

      true ->
        inspect(Map.get(task, :fun))
    end
  end

  defp describe_schedule_task(_), do: "(callback)"

end
