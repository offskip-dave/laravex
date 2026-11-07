defmodule Laravex.Generators do
  @moduledoc "Artisan make:* stub generators."

  def make_model(name, flags) do
    table = Macro.underscore(name) <> "s"

    stub("Models", name, """
    defmodule App.Models.#{name} do
      defstruct [:id, :created_at, :updated_at]
      use Laravex.Eloquex.Model, table: "#{table}"
      def fillable, do: []
      def casts, do: %{}
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
        %{}
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

  def make_resource(name) do
    stub("Http/Resources", name, """
    defmodule App.Http.Resources.#{name} do
      use Laravex.Http.Resource

      def to_map(model) do
        %{id: Map.get(model, :id)}
      end
    end
    """)
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

  def stub(subdir, name, contents) do
    path =
      Path.join([Laravex.Foundation.Application.base_path(), "app", subdir, Macro.underscore(name) <> ".ex"])

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
    IO.puts("Created: #{path}")
    :ok
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
