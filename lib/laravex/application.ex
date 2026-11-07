defmodule Laravex.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    base_path = File.cwd!()

    children = [
      Laravex.Container,
      Laravex.Cache.Manager,
      Laravex.Queue.Worker,
      Laravex.Events.Dispatcher,
      Laravex.Broadcasting.Broadcaster,
      {Laravex.Foundation.Server, base_path: base_path}
    ]

    opts = [strategy: :one_for_one, name: Laravex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
