defmodule Laravex.Bus do
  @moduledoc """
  Synchronous job chain (Laravel Bus::chain lite — no batches yet).

      Laravex.Bus.chain([
        {App.Jobs.ProcessPodcast, [1]},
        {App.Jobs.OptimizePodcast, [1]}
      ])
  """

  def chain(jobs) when is_list(jobs) do
    Enum.each(jobs, fn
      {mod, args} when is_atom(mod) ->
        Laravex.Queue.Worker.dispatch_sync(mod, List.wrap(args))

      mod when is_atom(mod) ->
        Laravex.Queue.Worker.dispatch_sync(mod, [])

      other ->
        raise ArgumentError, "Bus.chain expects {JobMod, args} or JobMod, got: #{inspect(other)}"
    end)

    :ok
  end

  def dispatch(job_mod, args \\ [], opts \\ []) when is_atom(job_mod) do
    Laravex.Queue.Worker.push(job_mod, List.wrap(args), opts)
  end

  def dispatch_sync(job_mod, args \\ []) when is_atom(job_mod) do
    Laravex.Queue.Worker.dispatch_sync(job_mod, List.wrap(args))
  end
end
