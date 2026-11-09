defmodule Laravex.Support.RedisPool do
  @moduledoc "Lazy Redix pool for `REDIS_CLIENT=native`."
  use GenServer

  @registry Laravex.Support.RedisPoolRegistry

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_) do
    {:ok, _} = Registry.start_link(keys: :unique, name: @registry)
    {:ok, %{}}
  end

  def command(args, opts \\ []) when is_list(args) do
    conn = Keyword.get(opts, :connection, "default")
    pid = ensure!(conn, opts)

    case Redix.command(pid, Enum.map(args, &to_string/1)) do
      {:ok, value} -> {:ok, value}
      {:error, %Redix.Error{message: msg}} -> {:error, msg}
      {:error, reason} -> {:error, reason}
    end
  end

  def ensure!(connection, opts \\ []) do
    connection = to_string(connection)

    case GenServer.call(__MODULE__, {:ensure, connection, opts}, 30_000) do
      {:ok, pid} -> pid
      {:error, reason} -> raise "Redis native pool error: #{inspect(reason)}"
    end
  end

  @impl true
  def handle_call({:ensure, connection, opts}, _from, state) do
    case Registry.lookup(@registry, connection) do
      [{pid, _}] ->
        {:reply, {:ok, pid}, state}

      [] ->
        case start_redix(connection, opts) do
          {:ok, pid} -> {:reply, {:ok, pid}, state}
          {:error, {:already_started, pid}} -> {:reply, {:ok, pid}, state}
          other -> {:reply, other, state}
        end
    end
  end

  defp start_redix(connection, opts) do
    cfg = Laravex.Support.RedisClient.config(connection)
    tls? = tls?(opts, cfg)

    redix_opts =
      [
        host: Keyword.get(opts, :host, cfg.host),
        port: Keyword.get(opts, :port, cfg.port),
        database: Keyword.get(opts, :database, cfg.database),
        name: {:via, Registry, {@registry, connection}}
      ]
      |> maybe_password(cfg.password)
      |> maybe_tls(tls?)

    Redix.start_link(redix_opts)
  end

  defp maybe_password(opts, nil), do: opts
  defp maybe_password(opts, ""), do: opts
  defp maybe_password(opts, password), do: Keyword.put(opts, :password, to_string(password))

  defp maybe_tls(opts, false), do: opts

  defp maybe_tls(opts, true) do
    Keyword.merge(opts,
      ssl: true,
      socket_opts: [verify: :verify_none]
    )
  end

  defp tls?(opts, cfg) do
    cond do
      Keyword.has_key?(opts, :tls) -> Keyword.get(opts, :tls) in [true, "true", "1"]
      true ->
        scheme = to_string(Map.get(cfg, :scheme) || System.get_env("REDIS_TLS") || "false")
        scheme in ["true", "1", "tls", "rediss"]
    end
  end
end
