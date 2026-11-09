defmodule Laravex.Generators do
  @moduledoc "Artisan make:* stub generators."

  def make_model(name, flags) do
    table = Macro.underscore(name) <> "s"

    stub("Models", name, """
    defmodule App.Models.#{name} do
      defstruct [:id, :created_at, :updated_at]
      use Laravex.Eloquex.Model, table: "#{table}"
      def fillable, do: []
      def guarded, do: ["*"]
      def casts, do: %{}
      def appends, do: []
      def touches, do: []
    end
    """)

    if "-m" in flags or "--migration" in flags do
      make_migration("create_#{table}_table", table: table)
    end

    if "-c" in flags or "--controller" in flags do
      make_controller("#{name}Controller")
    end

    if "-f" in flags or "--factory" in flags do
      make_factory("#{name}Factory")
    end

    :ok
  end

  def make_controller(name) do
    stub("Http/Controllers", name, """
    defmodule App.Http.Controllers.#{name} do
      use App.Http.Controllers.Controller

      def index(_request), do: Laravex.Http.Response.json(%{data: []})
      def show(request), do: Laravex.Http.Response.json(%{id: request.route_params["id"]})
      def store(_request), do: Laravex.Http.Response.json(%{created: true}, 201)
      def update(_request), do: Laravex.Http.Response.json(%{updated: true})
      def destroy(_request), do: Laravex.Http.Response.new(204, "")
    end
    """)
  end

  def make_migration(name, opts \\ []) do
    table = Keyword.get(opts, :table) || table_from_migration_name(name)
    ts = Calendar.strftime(DateTime.utc_now(), "%Y_%m_%d_%H%M%S")
    file = "#{ts}_#{name}.ex"
    mod = Macro.camelize(name)
    path = Path.join([Laravex.Foundation.Application.base_path(), "database/migrations", file])

    File.write!(path, """
    defmodule Database.Migrations.#{mod} do
      def up do
        Laravex.Database.Schema.create("#{table}", fn t ->
          t
          |> Laravex.Database.Blueprint.id()
          |> Laravex.Database.Blueprint.timestamps()
        end)
      end

      def down do
        Laravex.Database.Schema.drop_if_exists("#{table}")
      end
    end
    """)

    IO.puts("Migration created: database/migrations/#{file}")
  end

  def make_event(name) do
    stub("Events", name, """
    defmodule App.Events.#{name} do
      defstruct [:payload]
    end
    """)
  end

  def make_listener(name, opts \\ []) do
    stub("Listeners", name, """
    defmodule App.Listeners.#{name} do
      def handle(event), do: :ok
    end
    """)

    case Keyword.get(opts, :event) do
      event when is_binary(event) and event != "" ->
        wire_event_listener(event, name)

      _ ->
        :ok
    end
  end

  def wire_event_listener(event_name, listener_name) do
    path =
      Path.join(Laravex.Foundation.Application.base_path(), "app/Providers/event_service_provider.ex")

    contents = File.read!(path)
    event_mod = "App.Events.#{event_name}"
    listener_mod = "App.Listeners.#{listener_name}"
    entry = "      #{event_mod} => #{listener_mod},"

    cond do
      String.contains?(contents, entry) ->
        :ok

      String.contains?(contents, "def listen do\n    %{") ->
        updated =
          String.replace(
            contents,
            "def listen do\n    %{",
            "def listen do\n    %{\n" <> entry,
            global: false
          )

        File.write!(path, updated)
        IO.puts("Registered #{listener_mod} for #{event_mod} in EventServiceProvider.")

      String.contains?(contents, "def listen do\n    %{}") ->
        updated =
          String.replace(
            contents,
            "def listen do\n    %{}",
            "def listen do\n    %{\n" <> entry <> "\n    }",
            global: false
          )

        File.write!(path, updated)
        IO.puts("Registered #{listener_mod} for #{event_mod} in EventServiceProvider.")

      true ->
        IO.puts(:stderr, "Could not auto-wire EventServiceProvider; add mapping manually.")
    end

    :ok
  end

  def make_factory(name) do
    path =
      Path.join([
        Laravex.Foundation.Application.base_path(),
        "database/factories",
        Macro.underscore(name) <> ".ex"
      ])

    File.mkdir_p!(Path.dirname(path))
    model = String.replace_suffix(name, "Factory", "")

    File.write!(path, """
    defmodule Database.Factories.#{name} do
      use Laravex.Eloquex.Factory, model: App.Models.#{model}

      def definition do
        %{
          "name" => Laravex.Support.Faker.name(),
          "email" => Laravex.Support.Faker.email()
        }
      end
    end
    """)

    IO.puts("Factory created: #{path}")
  end

  def make_seeder(name) do
    path =
      Path.join([
        Laravex.Foundation.Application.base_path(),
        "database/seeders",
        Macro.underscore(name) <> ".ex"
      ])

    File.write!(path, """
    defmodule Database.Seeders.#{name} do
      def run, do: :ok
    end
    """)

    IO.puts("Seeder created: #{path}")
  end

  def make_policy(name) do
    model = String.replace_suffix(name, "Policy", "")

    stub("Policies", name, """
    defmodule App.Policies.#{name} do
      @moduledoc "Authorization policy for #{model}."

      def view?(user, _model), do: not is_nil(user)
      def create?(user), do: not is_nil(user)
      def update?(user, _model), do: not is_nil(user)
      def delete?(user, _model), do: not is_nil(user)
    end
    """)
  end

  def make_middleware(name) do
    stub("Http/Middleware", name, """
    defmodule App.Http.Middleware.#{name} do
      def handle(request, _opts), do: {:ok, request}
    end
    """)
  end

  def make_resource(name, opts \\ []) do
    if Keyword.get(opts, :collection, false) do
      collects = Keyword.get(opts, :collects) || resource_name_for_collection(name)

      stub("Http/Resources", name, """
      defmodule App.Http.Resources.#{name} do
        use Laravex.Http.ResourceCollection, collects: App.Http.Resources.#{collects}

        def additional(_resources), do: %{}
      end
      """)
    else
      stub("Http/Resources", name, """
      defmodule App.Http.Resources.#{name} do
        use Laravex.Http.Resource

        def to_map(model) do
          %{id: Map.get(model, :id)}
        end
      end
      """)
    end
  end

  defp resource_name_for_collection(name) do
    name
    |> to_string()
    |> String.replace_suffix("Collection", "")
    |> then(fn base ->
      if String.ends_with?(base, "Resource"), do: base, else: base <> "Resource"
    end)
  end

  def make_command(name) do
    cmd = Macro.underscore(name)
    File.mkdir_p!(Path.join(Laravex.Foundation.Application.base_path(), "app/Console"))

    File.write!(
      Path.join(Laravex.Foundation.Application.base_path(), "app/Console/#{cmd}.ex"),
      """
      defmodule App.Console.#{name} do
        def handle(io), do: io.writeln.("#{name} command")
      end
      """
    )

    console = Path.join(Laravex.Foundation.Application.base_path(), "routes/console.ex")
    contents = File.read!(console)

    snippet = """

        Router.command("#{cmd}", "#{name}", fn io ->
          App.Console.#{name}.handle(io)
        end)
    """

    marker = ~s(Router.command("#{cmd}")

    unless String.contains?(contents, marker) do
      updated =
        if String.contains?(contents, "def register do") do
          String.replace(contents, "def register do", "def register do" <> snippet, global: false)
        else
          contents <> "\n" <> snippet
        end

      File.write!(console, updated)
    end

    IO.puts("Command created: app/Console/#{cmd}.ex (registered in routes/console.ex)")
    :ok
  end

  def make_job(name) do
    stub("Jobs", name, """
    defmodule App.Jobs.#{name} do
      @moduledoc \"\"\"
      Queued job. Use `queue: false` for sync-only jobs.

          App.Jobs.#{name}.dispatch([arg])
          App.Jobs.#{name}.dispatch([arg], tries: 3, backoff: 10)
          App.Jobs.#{name}.dispatch_sync([arg])
      \"\"\"

      use Laravex.Queue.Job, queue: true

      def handle(args) do
        # Perform work with `args` (list).
        {:ok, args}
      end
    end
    """)
  end

  def make_mail(name) do
    stub("Mail", name, """
    defmodule App.Mail.#{name} do
      use Laravex.Mail.Mailable

      def to, do: "user@example.com"
      def subject, do: "#{name}"
      def content, do: "Hello"
    end
    """)
  end

  def make_notification(name) do
    stub("Notifications", name, """
    defmodule App.Notifications.#{name} do
      def via(_notifiable), do: [:mail, :database, :log]

      def to_mail(user) do
        %{to: user.email, subject: "#{name}", body: "Hi"}
      end

      def to_array(user) do
        %{"message" => "#{name}", "email" => Map.get(user, :email)}
      end

      def to_database(user), do: to_array(user)
    end
    """)
  end

  def make_request(name) do
    stub("Http/Requests", name, """
    defmodule App.Http.Requests.#{name} do
      use Laravex.Http.FormRequest

      def authorize(_request), do: true

      def rules do
        %{
          "name" => "required|string|max:255"
        }
      end

      def messages do
        %{
          "name.required" => "A :attribute is required."
        }
      end

      def attributes do
        %{
          "name" => "name"
        }
      end
    end
    """)
  end

  def make_rule(name) do
    stub("Rules", name, """
    defmodule App.Rules.#{name} do
      @behaviour Laravex.Validation.Rule

      def passes?(_attribute, _value), do: true
      def message, do: "validation failed"
    end
    """)
  end

  def make_view(name) do
    path = view_path(name)

    File.mkdir_p!(Path.dirname(path))

    unless File.exists?(path) do
      File.write!(path, default_view_contents(name))
      IO.puts("View created: #{path}")
    else
      IO.puts(:stderr, "View already exists: #{path}")
    end

    :ok
  end

  def make_test(name, opts \\ []) do
    unit? = Keyword.get(opts, :unit, false)
    base_name = name |> String.replace_suffix("Test", "") |> Macro.camelize()
    mod = "Tests.#{if unit?, do: "Unit", else: "Feature"}.#{base_name}Test"

    dir =
      Path.join([
        Laravex.Foundation.Application.base_path(),
        "tests",
        if(unit?, do: "Unit", else: "Feature")
      ])

    path = Path.join(dir, Macro.underscore(base_name) <> "_test.exs")
    File.mkdir_p!(dir)

    File.write!(path, """
    defmodule #{mod} do
      use Laravex.TestCase, async: false

      test "example" do
        assert true
      end
    end
    """)

    IO.puts("Test created: #{path}")
    :ok
  end

  def make_observer(name) do
    model = String.replace_suffix(name, "Observer", "")
    stub("Observers", name, """
    defmodule App.Observers.#{name} do
      @moduledoc "Eloquex observer for App.Models.#{model}."

      def creating(_model), do: :ok
      def created(_model), do: :ok
      def updating(_model), do: :ok
      def updated(_model), do: :ok
      def saving(_model), do: :ok
      def saved(_model), do: :ok
      def deleting(_model), do: :ok
      def deleted(_model), do: :ok
    end
    """)
  end

  def make_enum(name) do
    stub("Enums", name, """
    defmodule App.Enums.#{name} do
      @moduledoc "Application enum (Laravel-style backed enum lite)."

      @values ~w(pending active completed)

      def values, do: @values

      def valid?(value), do: to_string(value) in @values

      def cast(value) when value in @values, do: value

      def cast(value) when is_binary(value) do
        if value in @values, do: value, else: nil
      end

      def cast(_), do: nil
    end
    """)
  end

  def make_component(name) do
    stub("View/Components", name, """
    defmodule App.View.Components.#{name} do
      @moduledoc "Blade component."

      def render(assigns) do
        Laravex.View.make("components.#{Macro.underscore(name)}", assigns)
      end
    end
    """)

    make_view("components/#{Macro.underscore(name)}")
  end

  def make_channel(name) do
    stub("Broadcasting", name, """
    defmodule App.Broadcasting.#{name} do
      @moduledoc "Broadcast channel authorization."

      def join(_user, _channel, _request), do: true
    end
    """)
  end

  def make_cast(name) do
    stub("Casts", name, """
    defmodule App.Casts.#{name} do
      @moduledoc "Custom Eloquex cast."

      def get(_model, _key, value, _attributes), do: value
      def set(_model, _key, value, _attributes), do: value
    end
    """)
  end

  def make_exception(name) do
    stub("Exceptions", name, """
    defmodule App.Exceptions.#{name} do
      defexception message: "#{name}", plug_status: 500

      @impl true
      def exception(opts) do
        msg = Keyword.get(opts, :message, "#{name}")
        %__MODULE__{message: msg}
      end
    end
    """)
  end

  def make_scope(name) do
    stub("Models/Scopes", name, """
    defmodule App.Models.Scopes.#{name} do
      @moduledoc "Reusable Eloquex query scope."

      def apply(query) do
        query
      end
    end
    """)
  end

  def make_provider(name) do
    stub("Providers", name, """
    defmodule App.Providers.#{name} do
      def register, do: :ok
      def boot, do: :ok
    end
    """)

    append_provider(name)
  end

  def stub(subdir, name, contents) do
    path =
      Path.join([Laravex.Foundation.Application.base_path(), "app", subdir, Macro.underscore(name) <> ".ex"])

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
    IO.puts("Created: #{path}")
    :ok
  end

  defp append_provider(name) do
    path = Path.join(Laravex.Foundation.Application.base_path(), "bootstrap/providers.ex")

    if File.exists?(path) do
      contents = File.read!(path)
      entry = "App.Providers.#{name}"

      cond do
        String.contains?(contents, entry) ->
          :ok

        String.contains?(contents, "def list do") ->
          updated =
            String.replace(
              contents,
              "def list do",
              "def list do\n    # #{entry} — uncomment after compile:\n    # #{entry},\n",
              global: false
            )

          File.write!(path, updated)
          IO.puts("Noted #{entry} in bootstrap/providers.ex (add to list when ready).")

        true ->
          :ok
      end
    end

    :ok
  end

  defp view_path(name) do
    rel =
      name
      |> Macro.underscore()
      |> String.replace(".", "/")
      |> then(fn p -> if String.ends_with?(p, ".blade.php"), do: p, else: p <> ".blade.php" end)

    Path.join([Laravex.Foundation.Application.base_path(), "resources/views", rel])
  end

  defp default_view_contents(name) do
    title = name |> Macro.underscore() |> String.replace("/", " — ")

    """
    <div>
      <h1>#{title}</h1>
    </div>
    """
  end

  defp table_from_migration_name(name) do
    cond do
      String.starts_with?(name, "create_") and String.ends_with?(name, "_table") ->
        name
        |> String.trim_leading("create_")
        |> String.trim_trailing("_table")

      true ->
        Macro.underscore(name)
    end
  end
end
