defmodule Laravex.Broadcasting.Broadcaster do
  @moduledoc """
  Event broadcasting bus (log/null/array drivers). Echo-compatible payload shape.
  """

  use GenServer

  @supported_drivers ~w(log null array)

  def start_link(_ \\ []), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_), do: {:ok, %{events: []}}

  def event(channel, event, payload \\ %{}) do
    GenServer.call(__MODULE__, {:event, channel, event, payload})
  end

  def to_others(channel, event, payload \\ %{}), do: event(channel, event, payload)

  def sent, do: GenServer.call(__MODULE__, :sent)

  def fake, do: GenServer.call(__MODULE__, :clear)

  @impl true
  def handle_call({:event, channel, event, payload}, _from, state) do
    driver = ensure_driver!()

    message = %{
      channel: to_string(channel),
      event: to_string(event),
      data: payload,
      at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case driver do
      "null" ->
        :ok

      "log" ->
        Laravex.Log.Logger.info("Broadcast", message)

      "array" ->
        :ok
    end

    {:reply, :ok, %{state | events: [message | state.events]}}
  end

  def handle_call(:sent, _from, state), do: {:reply, Enum.reverse(state.events), state}
  def handle_call(:clear, _from, _state), do: {:reply, :ok, %{events: []}}

  defp ensure_driver! do
    driver = to_string(Laravex.Config.Repository.get("broadcasting.default", "log"))

    unless driver in @supported_drivers do
      raise ArgumentError,
            "Broadcasting uses unsupported driver #{inspect(driver)}. " <>
              "Supported drivers: #{Enum.join(@supported_drivers, ", ")} " <>
              "(set BROADCAST_CONNECTION=log|null|array; reverb/pusher/ably are out of scope)."
    end

    driver
  end
end

defmodule Laravex.Broadcasting.ShouldBroadcast do
  @moduledoc "Behaviour for broadcastable events."
  @callback broadcast_on() :: String.t() | [String.t()]
  @callback broadcast_as() :: String.t()
  @callback broadcast_with() :: map()

  def broadcast(event_mod) when is_atom(event_mod) do
    channels = List.wrap(event_mod.broadcast_on())
    name = event_mod.broadcast_as()
    payload = event_mod.broadcast_with()

    Enum.each(channels, fn ch ->
      Laravex.Broadcasting.Broadcaster.event(ch, name, payload)
    end)

    :ok
  end
end
