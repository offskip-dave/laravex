defmodule Laravex.Database.Pool do
  @moduledoc """
  Optional DBConnection pools for native Hex adapters.

  Pools are started lazily on first use when `client: "native"` (or `DB_CLIENT=native`).
  """

  use GenServer

  @registry Laravex.Database.PoolRegistry

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @impl true
  def init(_opts) do
    {:ok, _} = Registry.start_link(keys: :unique, name: @registry)
    {:ok, %{}}
  end

  def via(name), do: {:via, Registry, {@registry, Laravex.Database.Resolver.normalize_name(name)}}

  def ensure_started!(name) do
    name = Laravex.Database.Resolver.normalize_name(name)

    case GenServer.call(__MODULE__, {:ensure, name}, 30_000) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to start native DB pool #{inspect(name)}: #{inspect(reason)}"
    end
  end

  def checkout(name, fun) when is_function(fun, 1) do
    name = Laravex.Database.Resolver.normalize_name(name)
    ensure_started!(name)

    case Registry.lookup(@registry, name) do
      [{pid, _}] ->
        fun.(pid)

      [] ->
        raise ArgumentError, "Native pool failed to start for #{inspect(name)}"
    end
  end

  def transaction(name, fun) when is_function(fun, 0) do
    checkout(name, fn pid ->
      run_transaction(name, pid, fun)
    end)
  end

  @impl true
  def handle_call({:ensure, name}, _from, state) do
    case Registry.lookup(@registry, name) do
      [{_pid, _}] ->
        {:reply, :ok, state}

      [] ->
        cfg = Laravex.Database.Connection.config(name)

        case start_pool(name, cfg) do
          {:ok, _pid} -> {:reply, :ok, state}
          {:error, {:already_started, _}} -> {:reply, :ok, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end
    end
  end

  defp start_pool(name, cfg) do
    opts = pool_opts(name, cfg) ++ [name: via(name)]

    case Laravex.Database.Resolver.normalize_name(name) do
      "sqlite" ->
        File.mkdir_p!(Path.dirname(opts[:database]))
        Exqlite.start_link(opts)

      name when name in ["pgsql", "postgres"] ->
        Postgrex.start_link(opts)

      name when name in ["mysql", "mariadb"] ->
        MyXQL.start_link(opts)

      "sqlsrv" ->
        Tds.start_link(opts)
    end
  end

  defp run_transaction(name, pid, fun) do
    case Laravex.Database.Resolver.normalize_name(name) do
      "sqlite" ->
        DBConnection.transaction(pid, fn _conn -> fun.() end)

      name when name in ["pgsql", "postgres"] ->
        Postgrex.transaction(pid, fn _conn -> fun.() end)

      name when name in ["mysql", "mariadb"] ->
        MyXQL.transaction(pid, fn _conn -> fun.() end)

      "sqlsrv" ->
        Tds.transaction(pid, fn _conn -> fun.() end)
    end
  end

  defp pool_opts("sqlite", cfg) do
    database =
      Map.get(cfg, "database") ||
        Path.join(File.cwd!(), "database/database.sqlite")

    [
      database: to_string(database),
      pool: DBConnection.ConnectionPool,
      pool_size: pool_size(cfg)
    ]
  end

  defp pool_opts(name, cfg) when name in ["pgsql", "postgres"] do
    [
      hostname: to_string(Map.get(cfg, "host", "127.0.0.1")),
      port: to_int(Map.get(cfg, "port", 5432)),
      username: to_string(Map.get(cfg, "username", "postgres")),
      password: to_string(Map.get(cfg, "password", "")),
      database: to_string(Map.get(cfg, "database", "laravex")),
      pool_size: pool_size(cfg)
    ]
  end

  defp pool_opts(name, cfg) when name in ["mysql", "mariadb"] do
    [
      hostname: to_string(Map.get(cfg, "host", "127.0.0.1")),
      port: to_int(Map.get(cfg, "port", 3306)),
      username: to_string(Map.get(cfg, "username", "root")),
      password: to_string(Map.get(cfg, "password", "")),
      database: to_string(Map.get(cfg, "database", "laravex")),
      pool_size: pool_size(cfg)
    ]
  end

  defp pool_opts("sqlsrv", cfg) do
    [
      hostname: to_string(Map.get(cfg, "host", "localhost")),
      port: to_int(Map.get(cfg, "port", 1433)),
      username: to_string(Map.get(cfg, "username", "sa")),
      password: to_string(Map.get(cfg, "password", "")),
      database: to_string(Map.get(cfg, "database", "laravex")),
      pool_size: pool_size(cfg)
    ]
  end

  defp pool_size(cfg) do
    case Map.get(cfg, "pool") || System.get_env("DB_POOL_SIZE") || "5" do
      n when is_integer(n) -> n
      n when is_binary(n) -> String.to_integer(n)
      _ -> 5
    end
  end

  defp to_int(n) when is_integer(n), do: n
  defp to_int(n) when is_binary(n), do: String.to_integer(n)
  defp to_int(_), do: 0
end
