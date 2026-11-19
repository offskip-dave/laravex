defmodule Laravex.Queue do
  @moduledoc """
  Queue facade helpers (Laravel `Queue` manager subset).
  """

  @longer_key :laravex_queue_longer_than

  @doc """
  Register a callback when a job runs longer than `threshold` milliseconds
  (Laravel `Queue::whenJobRunsLongerThan`).

  Handler receives `(job_mod, duration_ms)`.
  """
  def when_job_runs_longer_than(threshold, handler)
      when is_number(threshold) and is_function(handler, 2) do
    hooks = Process.get(@longer_key, [])
    Process.put(@longer_key, hooks ++ [{threshold * 1.0, handler}])
    :ok
  end

  @doc false
  def notify_job_duration(job_mod, duration_ms) when is_number(duration_ms) do
    hooks = Process.get(@longer_key, [])

    Enum.each(hooks, fn {threshold, handler} ->
      if duration_ms > threshold, do: handler.(job_mod, duration_ms)
    end)

    :ok
  rescue
    _ -> :ok
  end

  def push(job_mod, args \\ [], opts \\ []), do: Laravex.Queue.Worker.push(job_mod, args, opts)
end
