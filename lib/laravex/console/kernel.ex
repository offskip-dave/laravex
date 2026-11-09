defmodule Laravex.Console.Kernel do
  @moduledoc "Artisan command dispatcher."

  alias Laravex.Console.Output

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
    "db:table" => {&__MODULE__.cmd_db_table/1, "Show the structure of a database table"},
    "model:show" => {&__MODULE__.cmd_model_show/1, "Show information about an Eloquex model"},
    "vendor:publish" => {&__MODULE__.cmd_vendor_publish/1, "Publish tagged framework assets"},
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
    "queue:listen" => {&__MODULE__.cmd_queue_listen/1, "Listen for queue jobs continuously"},
    "queue:failed" => {&__MODULE__.cmd_queue_failed/1, "List all of the failed queue jobs"},
    "queue:retry" => {&__MODULE__.cmd_queue_retry/1, "Retry a failed queue job"},
    "queue:forget" => {&__MODULE__.cmd_queue_forget/1, "Delete a failed queue job"},
    "queue:flush" => {&__MODULE__.cmd_queue_flush/1, "Flush all of the failed queue jobs"},
    "queue:batches" => {&__MODULE__.cmd_queue_batches/1, "List the job batches"},
    "queue:batch" => {&__MODULE__.cmd_queue_batch/1, "Show or cancel a job batch"},
    "sanctum:prune-expired" => {&__MODULE__.cmd_prune_tokens/1, "Prune expired API tokens"},
    "schedule:run" => {&__MODULE__.cmd_schedule/1, "Run due scheduled tasks"},
    "schedule:work" => {&__MODULE__.cmd_schedule_work/1, "Start the schedule worker loop"},
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
    "make:resource" => {&__MODULE__.cmd_make_resource/1, "Create an API resource (--collection)"},
    "make:factory" => {&__MODULE__.cmd_make_factory/1, "Create a factory"},
    "make:seeder" => {&__MODULE__.cmd_make_seeder/1, "Create a seeder"},
    "make:view" => {&__MODULE__.cmd_make_view/1, "Create a Blade view"},
    "make:test" => {&__MODULE__.cmd_make_test/1, "Create a test class"},
    "make:observer" => {&__MODULE__.cmd_make_observer/1, "Create a model observer"},
    "make:enum" => {&__MODULE__.cmd_make_enum/1, "Create an enum"},
    "make:component" => {&__MODULE__.cmd_make_component/1, "Create a Blade component"},
    "make:channel" => {&__MODULE__.cmd_make_channel/1, "Create a broadcast channel"},
    "make:cast" => {&__MODULE__.cmd_make_cast/1, "Create a custom cast class"},
    "make:exception" => {&__MODULE__.cmd_make_exception/1, "Create an exception class"},
    "make:scope" => {&__MODULE__.cmd_make_scope/1, "Create an Eloquex query scope"},
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
                Output.error("Command \"#{command}\" is not defined.")
                System.halt(1)
            end
        end
    end
  end

  def commands, do: @commands

  def cmd_inspire(_), do: Output.line(Laravex.Support.Inspiring.quote_text())

  def cmd_list(_) do
    version = Application.spec(:laravex, :vsn) |> to_string()
    Output.line("<options=bold>Laravex</> <fg=green;options=bold>Framework</> <fg=yellow>#{version}</>")
    Output.writeln()
    Output.line("<comment>Usage:</comment>")
    Output.line("  command [options] [arguments]")
    Output.writeln()
    Output.line("<comment>Available commands:</comment>")

    @commands
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.group_by(fn {name, _} ->
      case String.split(name, ":", parts: 2) do
        [ns, _] -> ns
        _ -> ""
      end
    end)
    |> Enum.sort_by(fn {ns, _} -> ns end)
    |> Enum.each(fn {ns, cmds} ->
      if ns != "" do
        Output.line(" <comment>#{ns}</comment>")
      end

      width =
        cmds
        |> Enum.map(fn {name, _} -> String.length(name) end)
        |> Enum.max(fn -> 0 end)
        |> max(18)

      Enum.sort_by(cmds, fn {name, _} -> name end)
      |> Enum.each(fn {name, {_, desc}} ->
        padded = String.pad_trailing(name, width + 2)
        Output.line("  <info>#{padded}</info>#{desc}")
      end)
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
    Output.info("Server running on <fg=cyan>http://127.0.0.1:#{actual}</>.")
    Process.sleep(:infinity)
  end

  def cmd_migrate(_), do: (Laravex.Database.Migrator.migrate(); :ok)
  def cmd_rollback(_), do: (Laravex.Database.Migrator.rollback(); :ok)
  def cmd_refresh(_), do: (Laravex.Database.Migrator.refresh(); :ok)

  def cmd_fresh(_) do
    Laravex.Database.Migrator.fresh()
    Output.info("Dropped all tables and re-ran all migrations.")
    :ok
  end

  def cmd_wipe(_) do
    Laravex.Database.Migrator.wipe()
    Output.info("Dropped all tables successfully.")
    :ok
  end

  def cmd_status(_) do
    Laravex.Database.Migrator.status()
    |> Enum.each(fn %{migration: m, status: s} ->
      label = String.pad_trailing(to_string(s), 10)

      painted =
        case String.downcase(to_string(s)) do
          "ran" -> "<fg=green;options=bold>#{label}</>"
          "pending" -> "<fg=yellow;options=bold>#{label}</>"
          _ -> "<comment>#{label}</comment>"
        end

      Output.line("  #{painted}#{m}")
    end)
  end

  def cmd_seed(_) do
    _ = Database.Seeders.DatabaseSeeder.run()
    Output.info("Database seeding completed successfully.")
    :ok
  end

  def cmd_routes(_) do
    routes = Laravex.Routing.Router.routes()

    if routes == [] do
      Output.comment("  No routes defined.")
    else
      Output.line(
        "  <fg=gray>" <>
          String.pad_trailing("Method", 8) <>
          String.pad_trailing("URI", 40) <>
          "Name</>"
      )

      Enum.each(routes, fn r ->
        method = String.pad_trailing(to_string(r.method), 8)
        uri = String.pad_trailing(to_string(r.uri), 40)
        name = to_string(r.name || "")
        Output.line("  <info>#{method}</info>#{uri}<fg=yellow>#{name}</>")
      end)
    end
  end

  def cmd_config_cache(_) do
    Laravex.Config.Repository.cache!()
    Output.info("Configuration cached successfully.")
  end

  def cmd_config_clear(_) do
    Laravex.Config.Repository.clear_cache!()
    Output.info("Configuration cache cleared successfully.")
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
    Output.info("Routes cached successfully.")
  end

  def cmd_route_clear(_) do
    Laravex.Routing.RouteCache.clear!()
    Output.info("Route cache cleared successfully.")
  end

  def cmd_route_match([method, uri | _]) do
    request = Laravex.Http.Request.capture(method, uri)

    case Laravex.Routing.Router.match(request) do
      :error ->
        Output.warn("No matching route for #{String.upcase(method)} #{uri}.")

      {:ok, req, handler, opts} ->
        name = Keyword.get(opts, :name, "—")
        Output.section("Match")
        Output.two_column_detail("Method", String.upcase(method))
        Output.two_column_detail("URI", uri)
        Output.two_column_detail("Name", name)
        Output.two_column_detail("Params", inspect(req.route_params))
        Output.two_column_detail("Action", inspect(handler))
        Output.writeln()
    end

    :ok
  end

  def cmd_route_match(_), do: usage("route:match", "{method} {uri}")

  def cmd_cache_clear(_) do
    Laravex.Cache.Manager.flush()
    Output.info("Application cache cleared successfully.")
    :ok
  end

  def cmd_cache_forget([key | _]) do
    Laravex.Cache.Manager.forget(key)
    Output.info("Forgot key [#{key}].")
    :ok
  end

  def cmd_cache_forget(_), do: usage("cache:forget", "{key}")

  def cmd_view_cache(_) do
    n = Laravex.View.Cache.warm()
    Output.info("Blade templates cached successfully (#{n} views).")
  end

  def cmd_view_clear(_) do
    Laravex.View.Cache.clear()
    Output.info("Compiled views cleared successfully.")
  end

  def cmd_optimize(_) do
    cmd_config_cache([])
    cmd_route_cache([])
    cmd_event_cache([])
    cmd_view_cache([])
    Output.info("Files cached successfully.")
  end

  def cmd_optimize_clear(_) do
    cmd_config_clear([])
    cmd_route_clear([])
    cmd_event_clear([])
    cmd_view_clear([])
    Output.info("Cached bootstrap files cleared successfully.")
  end

  def cmd_queue_work(args) do
    once = "--once" in args
    Laravex.Queue.Worker.work(once: once)
  end

  def cmd_queue_listen(args) do
    sleep =
      case Enum.find_value(args, fn
             "--sleep=" <> n -> String.to_integer(n)
             _ -> nil
           end) do
        nil -> 1
        n -> n
      end

    Output.info("Listening for queue jobs…")

    Stream.repeatedly(fn ->
      Laravex.Queue.Worker.work(once: true)
      Process.sleep(sleep * 1000)
      :ok
    end)
    |> Stream.run()
  end

  def cmd_queue_failed(_) do
    jobs = Laravex.Queue.Worker.failed_jobs()

    if jobs == [] do
      Output.info("No failed jobs!")
    else
      Output.line(
        "  <fg=gray>" <>
          String.pad_trailing("ID", 6) <>
          String.pad_trailing("UUID", 20) <>
          String.pad_trailing("Queue", 12) <>
          "Failed At</>"
      )

      Enum.each(jobs, fn job ->
        Output.line(
          "  " <>
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
      {:ok, _} -> Output.info("The failed job [#{id}] has been pushed back onto the queue!")
      {:error, :not_found} -> Output.error("No failed job matches the given ID [#{id}].")
      {:error, :bad_payload} -> Output.error("Unable to decode failed job payload.")
    end
  end

  def cmd_queue_retry(_), do: usage("queue:retry", "{id|uuid}")

  def cmd_queue_forget([id | _]) do
    case Laravex.Queue.Worker.forget_failed(id) do
      :ok -> Output.info("Failed job deleted successfully!")
      _ -> Output.error("No failed job matches the given ID [#{id}].")
    end
  end

  def cmd_queue_forget(_), do: usage("queue:forget", "{id|uuid}")

  def cmd_queue_flush(_) do
    Laravex.Queue.Worker.flush_failed()
    Output.info("All failed jobs deleted successfully!")
  end

  def cmd_queue_batches(_) do
    batches = Laravex.Bus.list_batches()

    if batches == [] do
      Output.comment("  No job batches found.")
    else
      Output.line(
        "  <fg=gray>" <>
          String.pad_trailing("ID", 38) <>
          String.pad_trailing("Name", 18) <>
          String.pad_trailing("Total", 8) <>
          String.pad_trailing("Pending", 10) <>
          String.pad_trailing("Failed", 8) <>
          "Cancelled</>"
      )

      Enum.each(batches, fn b ->
        Output.line(
          "  " <>
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
      {:ok, batch} -> Output.info("Batch [#{batch.id}] cancelled.")
      {:error, :not_found} -> Output.error("No batch matches the given ID [#{id}].")
    end
  end

  def cmd_queue_batch([id | _]) do
    case Laravex.Bus.find_batch(id) do
      nil ->
        Output.error("No batch matches the given ID [#{id}].")

      b ->
        Output.section("Batch")
        Output.two_column_detail("ID", b.id)
        Output.two_column_detail("Name", b.name)
        Output.two_column_detail("Total / Pending / Failed", "#{b.total_jobs} / #{b.pending_jobs} / #{b.failed_jobs}")
        Output.two_column_detail("Failed job ids", inspect(b.failed_job_ids))
        Output.two_column_detail("Created", b.created_at)
        Output.two_column_detail("Finished", b.finished_at)
        Output.two_column_detail("Cancelled", b.cancelled_at)
        Output.writeln()
    end
  end

  def cmd_queue_batch(_), do: usage("queue:batch", "{id} | cancel {id}")

  def cmd_prune_tokens(_) do
    Laravex.Auth.Token.prune_expired()
    Output.info("Expired API tokens pruned.")
  end

  def cmd_db_show(args) do
    table =
      Enum.find_value(args, fn
        "--table=" <> t -> t
        t -> if String.starts_with?(t, "-"), do: nil, else: t
      end)

    if table do
      cmd_db_table([table])
    else
      tables = Laravex.Database.Introspection.tables()
      Output.section("Database")

      Enum.each(tables, fn t ->
        Output.line("  <info>#{t}</info>")
      end)

      Output.writeln()
    end
  end

  def cmd_db_table([table | _]) when is_binary(table) do
    info = Laravex.Database.Introspection.table_info(table)
    Output.section("Table: #{info.name}")
    Output.line(
      "  <fg=gray>" <>
        String.pad_trailing("Column", 24) <>
        String.pad_trailing("Type", 12) <>
        "Nullable</>"
    )

    Enum.each(info.columns, fn col ->
      Output.line(
        "  <info>" <>
          String.pad_trailing(to_string(col["name"]), 24) <>
          "</info>" <>
          String.pad_trailing(to_string(col["type"]), 12) <>
          if(col["notnull"] in [0, "0"], do: "yes", else: "no")
      )
    end)

    if info.indexes != [] do
      Output.section("Indexes")
      Enum.each(info.indexes, fn idx -> Output.line("  #{inspect(idx)}") end)
    end

    Output.writeln()
  end

  def cmd_db_table(_), do: usage("db:table", "table")

  def cmd_vendor_publish(args) do
    tag =
      Enum.find_value(args, fn
        "--tag=" <> t -> t
        "--provider=" <> p -> p
        t -> if String.starts_with?(t, "-"), do: nil, else: t
      end) || "laravex"

    force? = "--force" in args
    Laravex.Publish.publish(tag, force: force?)
  end

  def cmd_model_show([name | _]) do
    case Laravex.Database.Introspection.resolve_model(name) do
      nil ->
        Output.error("Model [#{name}] not found.")

      mod ->
        info = Laravex.Database.Introspection.model_info(mod)
        Output.section(inspect(info.module))
        Output.two_column_detail("Table", info.table || "?")
        Output.two_column_detail("Soft deletes", info.soft_deletes?)
        Output.two_column_detail("Fillable", inspect(info.fillable))
        Output.two_column_detail("Guarded", inspect(info.guarded))
        Output.two_column_detail("Casts", inspect(info.casts))
        Output.two_column_detail("Appends", inspect(info.appends))
        Output.two_column_detail("Relations", inspect(info.relations))

        if info.columns != [] do
          Output.section("Columns")

          Enum.each(info.columns, fn col ->
            Output.line("  <info>#{col["name"]}</info> <fg=gray>(#{col["type"]})</>")
          end)
        end

        Output.writeln()
    end
  end

  def cmd_model_show(_), do: usage("model:show", "{Model}")

  def cmd_event_cache(_) do
    Laravex.Events.EventCache.cache!()
    Output.info("Events cached successfully.")
  end

  def cmd_event_clear(_) do
    Laravex.Events.EventCache.clear!()
    Output.info("Cached events cleared successfully.")
  end

  def cmd_schedule(_), do: Laravex.Console.Schedule.run()

  def cmd_schedule_work(args) do
    sleep =
      case Enum.find_value(args, fn
             "--sleep=" <> n -> String.to_integer(n)
             _ -> nil
           end) do
        nil -> 60
        n -> n
      end

    Output.info("Running scheduled tasks every #{sleep}s…")

    Stream.repeatedly(fn ->
      Laravex.Console.Schedule.run()
      Process.sleep(sleep * 1000)
      :ok
    end)
    |> Stream.run()
  end

  def cmd_schedule_list(_) do
    tasks = Laravex.Console.Schedule.all()

    if tasks == [] do
      Output.comment("  No scheduled tasks have been defined.")
    else
      Output.line(
        "  <fg=gray>" <> String.pad_trailing("Expression", 24) <> "Command / Callback</>"
      )

      Enum.each(tasks, fn task ->
        expr = Map.get(task, :expression) || "?"
        label = describe_schedule_task(task)
        Output.line("  <info>#{String.pad_trailing(to_string(expr), 24)}</info>#{label}")
      end)
    end
  end

  def cmd_event_list(_) do
    provider_map = event_provider_listen()
    runtime_map = event_runtime_listeners()
    merged = Map.merge(provider_map, runtime_map, fn _k, a, b -> List.wrap(a) ++ List.wrap(b) end)

    if map_size(merged) == 0 do
      Output.comment("  No events have been registered.")
    else
      merged
      |> Enum.sort_by(fn {event, _} -> to_string(event) end)
      |> Enum.each(fn {event, listeners} ->
        Output.line("  <fg=green;options=bold>#{inspect(event)}</>")

        Enum.each(Enum.uniq(List.wrap(listeners)), fn listener ->
          Output.line("    <fg=yellow>⇂</> #{inspect(listener)}")
        end)
      end)

      Output.writeln()
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
    elixir = System.version()
    otp = :erlang.system_info(:otp_release) |> to_string()
    version = Application.spec(:laravex, :vsn) |> to_string()

    Output.line(
      "<options=bold>Laravex Tinker</> <fg=gray>v#{version}</> " <>
        "<fg=gray>(Elixir #{elixir} — OTP #{otp})</>"
    )
    Output.line("<fg=gray>Type exit or quit to leave. Use <info>_</info> for the last result.</>")
    Output.writeln()
    tinker_loop([], nil)
  end

  def cmd_storage_link(_) do
    Laravex.Filesystem.Storage.link()
    Output.info("The links have been created.")
  end

  def cmd_down(args) do
    opts = parse_down_opts(args)
    Laravex.Foundation.Maintenance.down(opts)
    Output.info("Application is now in maintenance mode.")
  end

  def cmd_up(_) do
    Laravex.Foundation.Maintenance.up()
    Output.info("Application is now live.")
  end

  def cmd_about(_) do
    cfg = &Laravex.Config.Repository.get/2
    version = Application.spec(:laravex, :vsn) |> to_string()
    url = cfg.("app.url", "http://localhost") |> to_string() |> String.replace(~r/^https?:\/\//, "")
    debug? = truthy_config?(cfg.("app.debug", false))
    maintenance? = Laravex.Foundation.Maintenance.enabled?()

    Output.section("Environment")
    Output.two_column_detail("Application Name", cfg.("app.name", "Laravex"))
    Output.two_column_detail("Laravex Version", version)
    Output.two_column_detail("Elixir Version", System.version())
    Output.two_column_detail("OTP Release", :erlang.system_info(:otp_release))
    Output.two_column_detail("Environment", cfg.("app.env", "production"))
    Output.two_column_detail("Debug Mode", format_enabled(debug?))
    Output.two_column_detail("URL", url)
    Output.two_column_detail("Maintenance Mode", format_enabled(maintenance?))
    Output.two_column_detail("Timezone", cfg.("app.timezone", "UTC"))
    Output.two_column_detail("Locale", cfg.("app.locale", "en"))

    Output.section("Cache")
    Output.two_column_detail("Config", format_cached(config_cached?()))
    Output.two_column_detail("Events", format_cached(events_cached?()))
    Output.two_column_detail("Routes", format_cached(routes_cached?()))
    Output.two_column_detail("Views", format_cached(views_cached?()))

    Output.section("Drivers")
    Output.two_column_detail("Broadcasting", cfg.("broadcasting.default", "null"))
    Output.two_column_detail("Cache", cfg.("cache.default", "database"))
    Output.two_column_detail("Database", cfg.("database.default", "sqlite"))
    Output.two_column_detail("Logs", cfg.("logging.default", "stack"))
    Output.two_column_detail("Mail", cfg.("mail.default", "log"))
    Output.two_column_detail("Queue", cfg.("queue.default", "database"))
    Output.two_column_detail("Session", cfg.("session.driver", "database"))
    Output.writeln()
  end

  def cmd_env(args) do
    only =
      Enum.find_value(args, fn
        "--only=" <> key -> key
        _ -> nil
      end)

    Laravex.Env.all()
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.each(fn {k, v} ->
      if is_nil(only) or only == k do
        Output.line("<info>#{k}</info>=<comment>#{redact_env(k, v)}</comment>")
      end
    end)

    :ok
  end

  def cmd_key_generate(args) do
    force? = "--force" in args
    existing = Laravex.Env.get("APP_KEY")

    if present?(existing) and not force? do
      Output.warn("Application key already set. Use --force to overwrite.")
    else
      key = "base64:" <> Base.encode64(:crypto.strong_rand_bytes(32))
      Laravex.Env.write!("APP_KEY", key)
      Laravex.Config.Repository.load!(Laravex.Foundation.Application.base_path())
      Output.info("Application key set successfully.")
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
  def cmd_make_resource([name | rest]) do
    collection? = "--collection" in rest or "-c" in rest
    Laravex.Generators.make_resource(name, collection: collection?)
  end

  def cmd_make_resource(_), do: usage("make:resource", "Name [--collection]")
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
  def cmd_make_component([name | _]), do: Laravex.Generators.make_component(name)
  def cmd_make_component(_), do: usage("make:component", "Name")
  def cmd_make_channel([name | _]), do: Laravex.Generators.make_channel(name)
  def cmd_make_channel(_), do: usage("make:channel", "Name")
  def cmd_make_cast([name | _]), do: Laravex.Generators.make_cast(name)
  def cmd_make_cast(_), do: usage("make:cast", "Name")
  def cmd_make_exception([name | _]), do: Laravex.Generators.make_exception(name)
  def cmd_make_exception(_), do: usage("make:exception", "Name")
  def cmd_make_scope([name | _]), do: Laravex.Generators.make_scope(name)
  def cmd_make_scope(_), do: usage("make:scope", "Name")

  def cmd_install_api(_), do: Laravex.Install.api()
  def cmd_install_broadcasting(_), do: Laravex.Install.broadcasting()
  def cmd_install_starter(_), do: Laravex.Install.starter_kit()

  defp usage(cmd, arg) do
    Output.line("<comment>Usage:</comment> artisan <info>#{cmd}</info> #{arg}")
  end

  defp parse_down_opts(args) do
    Enum.reduce(args, [], fn
      "--message=" <> msg, acc -> Keyword.put(acc, :message, msg)
      "--retry=" <> n, acc -> Keyword.put(acc, :retry, String.to_integer(n))
      "--secret=" <> s, acc -> Keyword.put(acc, :secret, s)
      _, acc -> acc
    end)
  end

  defp present?(v), do: not (is_nil(v) or v == "")

  defp truthy_config?(v) when v in [true, "true", "1", 1, "on", "yes"], do: true
  defp truthy_config?(_), do: false

  defp format_enabled(true), do: "<fg=yellow;options=bold>ENABLED</>"
  defp format_enabled(false), do: "OFF"

  defp format_cached(true), do: "<fg=green;options=bold>CACHED</>"
  defp format_cached(false), do: "<fg=yellow;options=bold>NOT CACHED</>"

  defp config_cached? do
    base = Laravex.Foundation.Application.base_path()
    File.exists?(Path.join(base, "bootstrap/cache/config.term"))
  end

  defp events_cached?, do: Laravex.Events.EventCache.exists?()
  defp routes_cached?, do: Laravex.Routing.RouteCache.exists?()

  defp views_cached? do
    base = Laravex.Foundation.Application.base_path()
    dir = Path.join(base, "storage/framework/views")

    File.dir?(dir) and
      match?([_ | _], Path.wildcard(Path.join(dir, "*.blade")))
  end

  defp redact_env(key, value) do
    sensitive = ~w(KEY SECRET PASSWORD TOKEN PRIVATE)
    upper = String.upcase(to_string(key))

    if Enum.any?(sensitive, &String.contains?(upper, &1)) and present?(value) do
      "********"
    else
      inspect(value)
    end
  end

  defp tinker_loop(bindings, last) do
    prompt = Output.paint("<comment>>>> </comment>")

    case IO.gets(prompt) do
      :eof ->
        Output.writeln()
        :ok

      {:error, _} ->
        :ok

      line ->
        line = String.trim(line)

        cond do
          line in ["exit", "quit", ".exit"] ->
            Output.comment("Goodbye.")
            :ok

          line == "" ->
            tinker_loop(bindings, last)

          true ->
            bindings = Keyword.put(bindings, :_, last)

            try do
              {result, new_bindings} = Code.eval_string(line, bindings)
              tinker_dump(result)
              tinker_loop(Keyword.merge(bindings, new_bindings) |> Keyword.put(:_, result), result)
            rescue
              e ->
                Output.error(Exception.format(:error, e, []) |> String.trim())
                tinker_loop(bindings, last)
            catch
              kind, reason ->
                Output.error(Exception.format(kind, reason, []) |> String.trim())
                tinker_loop(bindings, last)
            end
        end
    end
  end

  defp tinker_dump(result) do
    inspected =
      inspect(result,
        pretty: true,
        syntax_colors: [
          atom: :cyan,
          string: :green,
          list: :default_color,
          boolean: :magenta,
          nil: :magenta,
          number: :yellow,
          map: :default_color,
          tuple: :default_color,
          binary: :green
        ]
      )

    IO.puts(inspected)
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
