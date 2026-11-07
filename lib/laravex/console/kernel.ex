defmodule Laravex.Console.Kernel do
  @moduledoc """
  Artisan-style console entrypoint.
  """

  def main(argv) do
    # Ensure application is started / booted
    Application.ensure_all_started(:laravex)
    Laravex.Foundation.Server.boot!()

    case argv do
      ["inspire" | _] ->
        Laravex.Console.Router.dispatch("inspire")

      [command | args] ->
        case Laravex.Console.Router.dispatch(command, args) do
          :ok -> :ok
          :not_found ->
            IO.puts(:stderr, "Command not found: #{command}")
            System.halt(1)
        end

      [] ->
        IO.puts("""
        Laravex Artisan

        Available commands:
          inspire    Display an inspiring quote
        """)
    end
  end
end
