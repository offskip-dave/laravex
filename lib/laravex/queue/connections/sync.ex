defmodule Laravex.Queue.Connections.Sync do
  @moduledoc false
  @behaviour Laravex.Queue.ConnectionAdapter

  @impl true
  def push(job_mod, args, opts), do: Laravex.Queue.Worker.push_sync(job_mod, args, opts)
end
