defmodule Routes.Console do
  @moduledoc "Port of routes/console.php"

  alias Laravex.Console.Router
  alias Laravex.Support.Inspiring

  def register do
    Laravex.Console.Schedule.reset()

    Router.command("inspire", "Display an inspiring quote", fn io ->
      io.writeln.(Inspiring.quote_text())
    end)

    Laravex.Console.Schedule.command("inspire", "hourly")
  end
end
