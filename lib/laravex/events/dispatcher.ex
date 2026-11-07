defmodule Laravex.Events.Dispatcher do
  @moduledoc "Event dispatcher with listener registration (sync + queued)."
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

  def listeners do
    GenServer.call(__MODULE__, :listeners)
  end

  @impl true
  def handle_call({:listen, event, listener}, _from, state) do
    listeners = Map.update(state.listeners, event, [listener], &(&1 ++ [listener]))
    {:reply, :ok, %{state | listeners: listeners}}
  end

  def handle_call({:dispatch, event, data}, _from, state) do
    Enum.each(Map.get(state.listeners, event, []), fn listener ->
      invoke_listener(listener, data)
    end)

    {:reply, :ok, state}
  end

  def handle_call(:listeners, _from, state) do
    {:reply, state.listeners, state}
  end

  defp invoke_listener(fun, data) when is_function(fun, 1), do: fun.(data)

  defp invoke_listener(mod, data) when is_atom(mod) do
    if queued_listener?(mod) do
      Laravex.Queue.Worker.push(Laravex.Events.CallQueuedListener, [mod, data])
    else
      apply(mod, :handle, [data])
    end
  end

  defp queued_listener?(mod) do
    Code.ensure_loaded?(mod) and function_exported?(mod, :should_queue?, 0) and mod.should_queue?()
  end
end

defmodule Laravex.Events.ShouldQueue do
  @moduledoc """
  Opt a listener into the queue (Laravel `ShouldQueue`).

      defmodule App.Listeners.SendWelcome do
        use Laravex.Events.ShouldQueue
        def handle(event), do: ...
      end
  """

  defmacro __using__(opts \\ []) do
    queue? = Keyword.get(opts, :queue, true)

    quote do
      def should_queue?, do: unquote(queue?)
      defoverridable should_queue?: 0
    end
  end
end

defmodule Laravex.Events.CallQueuedListener do
  @moduledoc false
  use Laravex.Queue.Job, queue: true

  def handle([listener, data]) when is_atom(listener) do
    apply(listener, :handle, [data])
  end
end
