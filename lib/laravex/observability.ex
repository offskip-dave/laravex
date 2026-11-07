defmodule Laravex.Observability do
  @moduledoc """
  Lightweight Telescope/Pulse-style request & job recording.
  """

  @table :laravex_telemetry

  def ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        :ets.new(@table, [:named_table, :public, :bag])
      rescue
        ArgumentError -> :ok
      end
    end

    :ok
  end

  def record_request(request, response) do
    ensure()

    :ets.insert(@table, {
      :request,
      %{
        method: request.method,
        path: request.path,
        status: response.status,
        at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    })
  end

  def record_job(job, result) do
    ensure()
    :ets.insert(@table, {:job, %{job: inspect(job), result: inspect(result), at: DateTime.utc_now()}})
  end

  def entries(type \\ :request) do
    ensure()
    :ets.lookup(@table, type) |> Enum.map(fn {_, v} -> v end)
  end
end
