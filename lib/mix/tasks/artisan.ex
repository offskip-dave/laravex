defmodule Mix.Tasks.Artisan do
  @moduledoc """
  Artisan-compatible Mix task: `mix artisan inspire`
  """
  use Mix.Task

  @shortdoc "Run Laravex artisan console commands"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Laravex.Console.Kernel.main(args)
  end
end
