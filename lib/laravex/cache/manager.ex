defmodule Laravex.Cache.Manager do
  @moduledoc "Cache manager with array/file/database stores."
  use GenServer

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(_), do: {:ok, %{array: %{}}}

  def put(key, value, ttl \\ nil) do
    GenServer.call(__MODULE__, {:put, to_string(key), value, ttl})
  end

  def get(key, default \\ nil) do
    GenServer.call(__MODULE__, {:get, to_string(key), default})
  end

  def forget(key), do: GenServer.call(__MODULE__, {:forget, to_string(key)})
  def flush, do: GenServer.call(__MODULE__, :flush)

  def remember(key, ttl, fun) when is_function(fun, 0) do
    case get(key) do
      nil ->
        value = fun.()
        put(key, value, ttl)
        value

      value ->
        value
    end
  end

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
    {:reply, :ok, %{state | array: Map.delete(state.array, key)}}
  end

  def handle_call(:flush, _from, _state), do: {:reply, :ok, %{array: %{}}}

  defp effective_store do
    store = Laravex.Config.Repository.get("cache.default", "array")

    if store == "database" and not safe_has_cache_table?() do
      "array"
    else
      store
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
