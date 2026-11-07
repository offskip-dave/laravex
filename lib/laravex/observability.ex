defmodule Laravex.Observability do
  @moduledoc """
  Lightweight Telescope/Pulse-style request & job recording.
  """

  @table :laravex_telemetry

  def ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        _ = :ets.new(@table, [:named_table, :public, :bag])
        :ok
      rescue
        ArgumentError -> :ok
      end
    else
      :ok
    end
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
