defmodule Laravex.Broadcasting.Drivers.Pubsub do
  @moduledoc """
  Local pub/sub via `Registry` (no Hex deps, no Reverb).
  """
  @behaviour Laravex.Broadcasting.Driver

  @registry Laravex.Broadcasting.PubsubRegistry

  @impl true
  def broadcast(%{channel: channel} = message) do
    ch = to_string(channel)

    Registry.dispatch(@registry, ch, fn entries ->
      Enum.each(entries, fn {pid, _} ->
        send(pid, {:laravex_broadcast, ch, message})
      end)
    end)

    :ok
  end

  @doc "Subscribe the caller process to a channel (local testing / SSE hooks)."
  def subscribe(channel) do
    Registry.register(@registry, to_string(channel), :ok)
  end

  @doc "Remove all registry subscriptions for the caller."
  def unsubscribe do
    Registry.unregister_match(@registry, :_, self())
    :ok
  end
end
