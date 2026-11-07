defmodule Laravex.Cache.Manager do
  @moduledoc "Cache manager with array/file/database stores."
  use GenServer

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(_), do: {:ok, %{array: %{}}}

  def put(key, value, ttl \\ nil) do
    GenServer.call(__MODULE__, {:put, to_string(key), value, ttl})
  end

  def forever(key, value), do: put(key, value, nil)

  def get(key, default \\ nil) do
    GenServer.call(__MODULE__, {:get, to_string(key), default})
  end

  @doc "Get many keys at once (Laravel `many` / `getMultiple`)."
  def many(keys) when is_list(keys) do
    Map.new(keys, fn key -> {to_string(key), get(key)} end)
  end

  @doc "Put many key/value pairs (Laravel `putMany` / `setMultiple`). Optional shared TTL."
  def put_many(values, ttl \\ nil) when is_map(values) do
    Enum.each(values, fn {k, v} -> put(k, v, ttl) end)
    :ok
  end

  def has?(key), do: get(key, :__missing__) != :__missing__

  @doc "Store value only if the key is missing. Returns true if stored."
  def add(key, value, ttl \\ nil) do
    if has?(key) do
      false
    else
      put(key, value, ttl)
      true
    end
  end

  def pull(key, default \\ nil) do
    value = get(key, default)
    forget(key)
    value
  end

  def forget(key), do: GenServer.call(__MODULE__, {:forget, to_string(key)})
  def flush, do: GenServer.call(__MODULE__, :flush)

  def remember(key, ttl, fun) when is_function(fun, 0) do
    case get(key, :__missing__) do
      :__missing__ ->
        value = fun.()
        put(key, value, ttl)
        value

      value ->
        value
    end
  end

  def remember_forever(key, fun) when is_function(fun, 0), do: remember(key, nil, fun)

  @doc """
  Stale-while-revalidate cache (Laravel `Cache::flexible` lite).

      flexible("users", [60, 120], fn -> fetch_users() end)
  """
  def flexible(key, [fresh, stale], fun)
      when is_function(fun, 0) and is_integer(fresh) and is_integer(stale) and fresh >= 0 and
             stale >= fresh do
    key = to_string(key)
    now = System.system_time(:second)

    case get(key, :__missing__) do
      :__missing__ ->
        store_flexible(key, fun.(), now, fresh, stale)

      {value, fresh_until, stale_until} when is_integer(fresh_until) and is_integer(stale_until) ->
        cond do
          now <= fresh_until ->
            value

          now <= stale_until ->
            _ = Task.start(fn -> refresh_flexible(key, fun, fresh, stale) end)
            value

          true ->
            store_flexible(key, fun.(), now, fresh, stale)
        end

      _other ->
        store_flexible(key, fun.(), now, fresh, stale)
    end
  end

  @doc "Process-dictionary memoization for the current process (Laravel `memo`)."
  def memo(key, fun) when is_function(fun, 0) do
    dict_key = {:laravex_cache_memo, to_string(key)}

    case Process.get(dict_key) do
      nil ->
        value = fun.()
        Process.put(dict_key, value)
        value

      value ->
        value
    end
  end

  defp store_flexible(key, value, now, fresh, stale) do
    put(key, {value, now + fresh, now + stale})
    value
  end

  defp refresh_flexible(key, fun, fresh, stale) do
    now = System.system_time(:second)

    try do
      put(key, {fun.(), now + fresh, now + stale})
    rescue
      _ -> :ok
    end
  end

  def increment(key, amount \\ 1) when is_number(amount) do
    GenServer.call(__MODULE__, {:increment, to_string(key), amount})
  end

  def decrement(key, amount \\ 1) when is_number(amount), do: increment(key, -amount)

  @doc """
  Atomic-ish cache lock (Laravel `Cache::lock` lite, no Redis).

      lock = Cache.lock(\"foo\", 10)
      if Cache.get_lock(lock), do: ..., Cache.release(lock)
  """
  def lock(name, seconds \\ 60) when is_integer(seconds) and seconds > 0 do
    %{name: to_string(name), seconds: seconds, owner: :erlang.unique_integer([:positive])}
  end

  def get_lock(%{name: name, seconds: seconds, owner: owner}) do
    key = lock_key(name)

    case get(key, :__missing__) do
      :__missing__ ->
        put(key, owner, seconds)
        true

      ^owner ->
        true

      _ ->
        false
    end
  end

  def release(%{name: name, owner: owner}) do
    key = lock_key(name)

    case get(key, :__missing__) do
      ^owner ->
        forget(key)
        true

      _ ->
        false
    end
  end

  @doc "Block until the lock is acquired or `seconds` elapses. Returns true/false."
  def block(%{name: _, seconds: _} = lock, seconds \\ 5) when is_integer(seconds) and seconds >= 0 do
    deadline = System.monotonic_time(:millisecond) + seconds * 1000
    do_block(lock, deadline)
  end

  defp do_block(lock, deadline) do
    if get_lock(lock) do
      true
    else
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        Process.sleep(50)
        do_block(lock, deadline)
      end
    end
  end

  defp lock_key(name), do: "lock:" <> to_string(name)

  @impl true
  def handle_call({:put, key, value, ttl}, _from, state) do
    store = Laravex.Cache.Resolver.effective()
    expires = if ttl, do: System.system_time(:second) + ttl, else: nil
    entry = %{value: value, expires: expires}
    store.put(key, entry, state)

    state =
      if store == Laravex.Cache.Stores.Array or store == Laravex.Cache.Stores.Database do
        %{state | array: Map.put(state.array, key, entry)}
      else
        state
      end

    {:reply, :ok, state}
  end

  def handle_call({:get, key, default}, _from, state) do
    store = Laravex.Cache.Resolver.effective()
    entry = store.get(key, state)

    value =
      cond do
        is_nil(entry) -> default
        entry.expires && entry.expires < System.system_time(:second) -> default
        true -> entry.value
      end

    {:reply, value, state}
  end

  def handle_call({:forget, key}, _from, state) do
    store = Laravex.Cache.Resolver.effective()
    store.forget(key)
    {:reply, :ok, %{state | array: Map.delete(state.array, key)}}
  end

  def handle_call(:flush, _from, _state), do: {:reply, :ok, %{array: %{}}}

  def handle_call({:increment, key, amount}, _from, state) do
    {value, state} = do_get_entry(key, state)

    next =
      case value do
        n when is_number(n) -> n + amount
        _ -> amount
      end

    {:reply, next, put_entry(state, key, %{value: next, expires: nil})}
  end

  defp do_get_entry(key, state) do
    store = Laravex.Cache.Resolver.effective()
    entry = store.get(key, state)

    value =
      cond do
        is_nil(entry) -> nil
        entry.expires && entry.expires < System.system_time(:second) -> nil
        true -> entry.value
      end

    {value, state}
  end

  defp put_entry(state, key, entry) do
    store = Laravex.Cache.Resolver.effective()
    store.put(key, entry, state)

    if store == Laravex.Cache.Stores.Array or store == Laravex.Cache.Stores.Database do
      %{state | array: Map.put(state.array, key, entry)}
    else
      state
    end
  end
end
