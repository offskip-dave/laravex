defmodule Laravex.Queue.Connections.Deferred do
  @moduledoc false
  @behaviour Laravex.Queue.ConnectionAdapter

  @impl true
  def push(job_mod, args, opts) do
    if Keyword.get(opts, :should_queue?, true) do
      Laravex.Queue.Worker.push_deferred(job_mod, args, opts)
    else
      Laravex.Queue.Worker.push_sync(job_mod, args, opts)
    end
  end
end
