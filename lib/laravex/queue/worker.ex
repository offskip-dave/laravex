defmodule Laravex.Queue.Worker do
  @moduledoc "Database queue: push jobs and process with queue:work."
  use GenServer

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(s), do: {:ok, s}

  def push(job_mod, args \\ [], opts \\ []) when is_atom(job_mod) do
    connection = Laravex.Config.Repository.get("queue.default", "database")

    case connection do
      "sync" ->
        job_mod.handle(args)
        :ok

      _ ->
        payload =
          Laravex.Support.JSON.encode!(%{
            "job" => Atom.to_string(job_mod),
            "args" => encode_args(args)
          })

        now = System.system_time(:second)
        queue = Keyword.get(opts, :queue, "default")

        Laravex.Database.Connection.execute(
          "INSERT INTO jobs (queue, payload, attempts, reserved_at, available_at, created_at) VALUES (?, ?, 0, NULL, ?, ?)",
          [queue, payload, now, now]
        )

        :ok
    end
  end

  def work(opts \\ []) do
    once = Keyword.get(opts, :once, false)
    do_work(once)
  end

  defp do_work(once) do
    now = System.system_time(:second)

    jobs =
      Laravex.Database.Connection.query(
        "SELECT * FROM jobs WHERE available_at <= ? AND reserved_at IS NULL ORDER BY id ASC LIMIT 1",
        [now]
      )

    case jobs do
      [job | _] ->
        process(job)
        unless once, do: do_work(false)
        :ok

      [] ->
        if once, do: :ok, else: (Process.sleep(1000); do_work(false))
    end
  end

  defp process(%{"id" => id, "payload" => payload} = job) do
    Laravex.Database.Connection.execute(
      "UPDATE jobs SET reserved_at = ?, attempts = attempts + 1 WHERE id = ?",
      [System.system_time(:second), id]
    )

    try do
      {:ok, data} = Laravex.Support.JSON.decode(payload)
      job_mod = resolve_job_module(data["job"])
      args = data["args"] || []
      job_mod.handle(args)
      Laravex.Database.Connection.execute("DELETE FROM jobs WHERE id = ?", [id])
    rescue
      e ->
        fail(job, e)
    end
  end

  defp resolve_job_module(name) when is_binary(name) do
    mod = String.to_atom(name)

    case Code.ensure_loaded(mod) do
      {:module, ^mod} ->
        mod

      {:error, reason} ->
        raise "Job module #{name} could not be loaded: #{inspect(reason)}"
    end
  end

  defp fail(%{"id" => id, "payload" => payload, "queue" => queue}, error) do
    Laravex.Database.Connection.execute("DELETE FROM jobs WHERE id = ?", [id])

    if Laravex.Database.Schema.has_table?("failed_jobs") do
      Laravex.Database.Connection.execute(
        "INSERT INTO failed_jobs (uuid, connection, queue, payload, exception, failed_at) VALUES (?, ?, ?, ?, ?, ?)",
        [
          Laravex.Support.Helpers.str_random(16),
          "database",
          queue,
          payload,
          Exception.message(error),
          DateTime.utc_now() |> DateTime.to_iso8601()
        ]
      )
    end
  end

  defp encode_args(args) when is_list(args), do: Enum.map(args, &to_string/1)
  defp encode_args(args), do: [to_string(args)]
end

defmodule Laravex.Queue.Job do
  @moduledoc "Base job behaviour."
  @callback handle(args :: list()) :: any()

  defmacro __using__(_opts) do
    quote do
      @behaviour Laravex.Queue.Job

      def dispatch(args \\ [], opts \\ []) do
        Laravex.Queue.Worker.push(__MODULE__, List.wrap(args), opts)
      end
    end
  end
end
