defmodule Laravex.Events.Dispatcher do
  @moduledoc "Event dispatcher with listener registration (sync + queued)."
  use GenServer

  def start_link(_ \\ []), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(_), do: {:ok, default_state()}

  defp default_state do
    %{listeners: %{}, fake: false, fake_run_listeners: false, recorded: []}
  end

  @doc """
  Fake event dispatch (Laravel `Event::fake`).

  Dispatched events are recorded; listeners are skipped unless `run_listeners: true`.
  """
  def fake(opts \\ []) do
    run? = Keyword.get(opts, :run_listeners, false)
    GenServer.call(__MODULE__, {:fake, run?})
  end

  def dispatched, do: GenServer.call(__MODULE__, :dispatched)

  def clear, do: GenServer.call(__MODULE__, :clear_recorded)

  def assert_dispatched(fun) when is_function(fun, 1) do
    Enum.any?(dispatched(), fun)
  end

  def assert_not_dispatched(fun) when is_function(fun, 1) do
    not assert_dispatched(fun)
  end

  def listen(event, listener) when is_atom(event) do
    GenServer.call(__MODULE__, {:listen, event, listener})
  end

  def dispatch(event, payload \\ nil) when is_atom(event) or is_struct(event) do
    {event_name, data} = unwrap_event(event, payload)
    GenServer.call(__MODULE__, {:dispatch, event_name, data, :each})
  end

  @doc """
  Dispatch until a listener returns a non-nil value (Laravel `Event::until`).
  Returns that value, or `nil` if none stop the chain.
  """
  def until(event, payload \\ nil) when is_atom(event) or is_struct(event) do
    {event_name, data} = unwrap_event(event, payload)
    GenServer.call(__MODULE__, {:dispatch, event_name, data, :until})
  end

  def dispatch_if(condition, event, payload \\ nil) do
    if truthy?(condition), do: dispatch(event, payload), else: false
  end

  def dispatch_unless(condition, event, payload \\ nil) do
    if truthy?(condition), do: false, else: dispatch(event, payload)
  end

  def listeners do
    GenServer.call(__MODULE__, :listeners)
  end

  defp unwrap_event(%mod{} = struct, _payload), do: {mod, struct}
  defp unwrap_event(atom, payload) when is_atom(atom), do: {atom, payload}

  defp truthy?(v) when v in [false, nil, 0, "", "0"], do: false
  defp truthy?(_), do: true

  @impl true
  def handle_call({:listen, event, listener}, _from, state) do
    listeners = Map.update(state.listeners, event, [listener], &(&1 ++ [listener]))
    {:reply, :ok, %{state | listeners: listeners}}
  end

  def handle_call({:dispatch, event, data, mode}, _from, state) do
    state =
      if state.fake do
        %{state | recorded: [%{event: event, payload: data} | state.recorded]}
      else
        state
      end

    reply =
      if state.fake and not state.fake_run_listeners do
        if mode == :until, do: nil, else: :ok
      else
        listeners = Map.get(state.listeners, event, [])

        case mode do
          :each ->
            Enum.each(listeners, &invoke_listener(&1, data))
            :ok

          :until ->
            Enum.reduce_while(listeners, nil, fn listener, _ ->
              case invoke_listener(listener, data) do
                nil -> {:cont, nil}
                false -> {:cont, nil}
                result -> {:halt, result}
              end
            end)
        end
      end

    {:reply, reply, state}
  end

  def handle_call({:fake, run_listeners?}, _from, state) do
    {:reply, :ok,
     %{state | fake: true, fake_run_listeners: run_listeners?, recorded: []}}
  end

  def handle_call(:dispatched, _from, state) do
    {:reply, Enum.reverse(state.recorded), state}
  end

  def handle_call(:clear_recorded, _from, state) do
    {:reply, :ok, %{state | recorded: []}}
  end

  def handle_call(:listeners, _from, state) do
    {:reply, state.listeners, state}
  end

  defp invoke_listener(fun, data) when is_function(fun, 1), do: fun.(data)

  defp invoke_listener(mod, data) when is_atom(mod) do
    if queued_listener?(mod) do
      Laravex.Queue.Worker.push(Laravex.Events.CallQueuedListener, [mod, data])
      nil
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
