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
    store = effective_store()
    expires = if ttl, do: System.system_time(:second) + ttl, else: nil
    entry = %{value: value, expires: expires}

    state =
      case store do
        "array" ->
          %{state | array: Map.put(state.array, key, entry)}

        "file" ->
          write_file(key, entry)
          state

        "database" ->
          write_db(key, entry)
          %{state | array: Map.put(state.array, key, entry)}

        _ ->
          %{state | array: Map.put(state.array, key, entry)}
      end

    {:reply, :ok, state}
  end

  def handle_call({:get, key, default}, _from, state) do
    store = effective_store()

    entry =
      case store do
        "array" -> Map.get(state.array, key)
        "file" -> read_file(key) || Map.get(state.array, key)
        "database" -> read_db(key) || Map.get(state.array, key)
        _ -> Map.get(state.array, key)
      end

    value =
      cond do
        is_nil(entry) -> default
        entry.expires && entry.expires < System.system_time(:second) -> default
        true -> entry.value
      end

    {:reply, value, state}
  end

  def handle_call({:forget, key}, _from, state) do
    store = effective_store()

    case store do
      "file" -> forget_file(key)
      "database" -> forget_db(key)
      _ -> :ok
    end

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
    store = effective_store()

    entry =
      case store do
        "array" -> Map.get(state.array, key)
        "file" -> read_file(key) || Map.get(state.array, key)
        "database" -> read_db(key) || Map.get(state.array, key)
        _ -> Map.get(state.array, key)
      end

    value =
      cond do
        is_nil(entry) -> nil
        entry.expires && entry.expires < System.system_time(:second) -> nil
        true -> entry.value
      end

    {value, state}
  end

  defp put_entry(state, key, entry) do
    store = effective_store()

    case store do
      "array" ->
        %{state | array: Map.put(state.array, key, entry)}

      "file" ->
        write_file(key, entry)
        state

      "database" ->
        write_db(key, entry)
        %{state | array: Map.put(state.array, key, entry)}

      _ ->
        %{state | array: Map.put(state.array, key, entry)}
    end
  end

  defp forget_file(key) do
    path =
      Path.join(
        Laravex.Foundation.Application.base_path(),
        "storage/framework/cache/data/#{Base.encode16(key)}"
      )

    if File.exists?(path), do: File.rm(path)
    :ok
  end

  defp forget_db(key) do
    if Laravex.Database.Schema.has_table?("cache") do
      Laravex.Database.Connection.execute("DELETE FROM cache WHERE key = ?", [key])
    end

    :ok
  end

  @supported_drivers ~w(array file database)

  defp effective_store do
    name = to_string(Laravex.Config.Repository.get("cache.default", "array"))
    stores = Laravex.Config.Repository.get("cache.stores", %{})
    cfg = Map.get(stores, name) || Map.get(stores, String.to_atom(name)) || %{}
    driver = to_string(Map.get(cfg, "driver") || Map.get(cfg, :driver) || name)

    unless driver in @supported_drivers do
      raise ArgumentError,
            "Cache store #{inspect(name)} uses unsupported driver #{inspect(driver)}. " <>
              "Supported drivers: #{Enum.join(@supported_drivers, ", ")} " <>
              "(set CACHE_STORE=array|file|database)."
    end

    if driver == "database" and not safe_has_cache_table?() do
      "array"
    else
      driver
    end
  end

  defp safe_has_cache_table? do
    Laravex.Database.Schema.has_table?("cache")
  rescue
    _ -> false
  end

  defp write_file(key, entry) do
    dir = Path.join(Laravex.Foundation.Application.base_path(), "storage/framework/cache/data")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, Base.encode16(key)), :erlang.term_to_binary(entry))
  end

  defp read_file(key) do
    path =
      Path.join(
        Laravex.Foundation.Application.base_path(),
        "storage/framework/cache/data/#{Base.encode16(key)}"
      )

    if File.exists?(path), do: :erlang.binary_to_term(File.read!(path)), else: nil
  end

  defp write_db(key, entry) do
    if Laravex.Database.Schema.has_table?("cache") do
      Laravex.Database.Connection.execute("DELETE FROM cache WHERE key = ?", [key])

      Laravex.Database.Connection.execute(
        "INSERT INTO cache (key, value, expiration) VALUES (?, ?, ?)",
        [key, :erlang.term_to_binary(entry) |> Base.encode64(), entry.expires || 0]
      )
    end
  end

  defp read_db(key) do
    if Laravex.Database.Schema.has_table?("cache") do
      case Laravex.Database.Connection.query("SELECT value FROM cache WHERE key = ?", [key]) do
        [%{"value" => bin}] -> :erlang.binary_to_term(Base.decode64!(bin))
        _ -> nil
      end
    else
      nil
    end
  end
end
