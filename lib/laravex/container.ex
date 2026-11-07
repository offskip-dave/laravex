defmodule Laravex.Container do
  @moduledoc """
  Laravel-style service container: bind, singleton, make, call.
  """

  use GenServer

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state), do: {:ok, state}

  def bind(abstract, concrete) when is_atom(abstract) and is_function(concrete, 1) do
    GenServer.call(__MODULE__, {:bind, abstract, concrete, :bind})
  end

  def singleton(abstract, concrete) when is_atom(abstract) and is_function(concrete, 1) do
    GenServer.call(__MODULE__, {:bind, abstract, concrete, :singleton})
  end

  def instance(abstract, value) when is_atom(abstract) do
    GenServer.call(__MODULE__, {:instance, abstract, value})
  end

  def make(abstract, params \\ []) do
    GenServer.call(__MODULE__, {:make, abstract, params})
  end

  def call(fun_or_mfa, params \\ [])

  def call(fun, params) when is_function(fun) do
    fun.(params)
  end

  def call({mod, fun}, params) when is_atom(mod) and is_atom(fun) do
    apply(mod, fun, List.wrap(params))
  end

  def call({mod, fun, args}, extra) when is_atom(mod) and is_atom(fun) and is_list(args) do
    apply(mod, fun, args ++ List.wrap(extra))
  end

  def bound?(abstract) do
    GenServer.call(__MODULE__, {:bound?, abstract})
  end

  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @impl true
  def handle_call({:bind, abstract, concrete, type}, _from, state) do
    {:reply, :ok, Map.put(state, abstract, {type, concrete, nil})}
  end

  def handle_call({:instance, abstract, value}, _from, state) do
    {:reply, :ok, Map.put(state, abstract, {:instance, nil, value})}
  end

  def handle_call({:make, abstract, params}, _from, state) do
    case Map.get(state, abstract) do
      {:singleton, concrete, nil} ->
        value = concrete.(params)
        {:reply, value, Map.put(state, abstract, {:singleton, concrete, value})}

      {:singleton, _concrete, value} ->
        {:reply, value, state}

      {:bind, concrete, _} ->
        {:reply, concrete.(params), state}

      {:instance, _, value} ->
        {:reply, value, state}

      nil ->
        if function_exported?(abstract, :new, 0) do
          {:reply, abstract.new(), state}
        else
          {:reply, abstract, state}
        end
    end
  end

  def handle_call({:bound?, abstract}, _from, state) do
    {:reply, Map.has_key?(state, abstract), state}
  end

  def handle_call(:flush, _from, _state) do
    {:reply, :ok, %{}}
  end
end
