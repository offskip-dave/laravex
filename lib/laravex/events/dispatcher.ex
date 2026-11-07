defmodule Laravex.Events.Dispatcher do
  @moduledoc "Event dispatcher with listener registration."
  use GenServer

  def start_link(_ \\ []), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(_), do: {:ok, %{listeners: %{}}}

  def listen(event, listener) when is_atom(event) do
    GenServer.call(__MODULE__, {:listen, event, listener})
  end

  def dispatch(event, payload \\ nil) when is_atom(event) or is_struct(event) do
    {event_name, data} =
      case event do
        %mod{} = struct -> {mod, struct}
        atom when is_atom(atom) -> {atom, payload}
      end

    GenServer.call(__MODULE__, {:dispatch, event_name, data})
  end

  @impl true
  def handle_call({:listen, event, listener}, _from, state) do
    listeners = Map.update(state.listeners, event, [listener], &(&1 ++ [listener]))
    {:reply, :ok, %{state | listeners: listeners}}
  end

  def handle_call({:dispatch, event, data}, _from, state) do
    Enum.each(Map.get(state.listeners, event, []), fn
      fun when is_function(fun, 1) -> fun.(data)
      mod when is_atom(mod) -> apply(mod, :handle, [data])
    end)

    {:reply, :ok, state}
  end
end
