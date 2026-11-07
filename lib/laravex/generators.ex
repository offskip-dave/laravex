defmodule Laravex.Generators do
  @moduledoc "Artisan make:* stub generators."

  def make_model(name, flags) do
    stub("Models", name, """
    defmodule App.Models.#{name} do
      defstruct [:id, :created_at, :updated_at]
      use Laravex.Database.Model, table: "#{Macro.underscore(name)}s"
      def fillable, do: []
      def casts, do: %{}
    end
    """)

    if "-m" in flags or "--migration" in flags do
      make_migration("create_#{Macro.underscore(name)}s_table")
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

  def make_migration(name) do
    ts = Calendar.strftime(DateTime.utc_now(), "%Y_%m_%d_%H%M%S")
    file = "#{ts}_#{name}.ex"
    mod = Macro.camelize(name)
    path = Path.join([Laravex.Foundation.Application.base_path(), "database/migrations", file])

    File.write!(path, """
    defmodule Database.Migrations.#{mod} do
      def up do
        Laravex.Database.Schema.create("table_name", fn t ->
          t
          |> Laravex.Database.Blueprint.id()
          |> Laravex.Database.Blueprint.timestamps()
        end)
      end

      def down do
        Laravex.Database.Schema.drop_if_exists("table_name")
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

    File.write!(path, """
    defmodule Database.Factories.#{name} do
      def definition, do: %{}
      def make(attrs \\\\ %{}), do: Map.merge(definition(), attrs)
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

  def make_command(name) do
    stub_path = Path.join(Laravex.Foundation.Application.base_path(), "routes/console.ex")
    IO.puts("Register `#{Macro.underscore(name)}` in routes/console.ex")
    File.write!(
      Path.join(Laravex.Foundation.Application.base_path(), "app/Console/#{Macro.underscore(name)}.ex"),
      """
      defmodule App.Console.#{name} do
        def handle(io), do: io.writeln.("#{name} command")
      end
      """
    )

    _ = stub_path
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
end
