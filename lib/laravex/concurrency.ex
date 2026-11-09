defmodule Laravex.Concurrency do
  @moduledoc """
  Laravel Concurrency lite — run tasks concurrently via `Task.async_stream`.

      Laravex.Concurrency.run([
        fn -> :a end,
        fn -> :b end
      ])
  """

  def run(tasks, opts \\ []) when is_list(tasks) do
    max = Keyword.get(opts, :max_concurrency, System.schedulers_online())
    timeout = Keyword.get(opts, :timeout, 30_000)

    tasks
    |> Task.async_stream(fn fun -> fun.() end, max_concurrency: max, timeout: timeout, ordered: true)
    |> Enum.map(fn
      {:ok, value} -> value
      {:exit, reason} -> raise "Concurrency task failed: #{inspect(reason)}"
    end)
  end

  def defer(tasks, opts \\ []) when is_list(tasks) do
    Task.start(fn -> run(tasks, opts) end)
    :ok
  end
end
