defmodule Laravex.Support.RedisClient do
  @moduledoc """
  Redis client facade.

  Default: RESP over `:gen_tcp` (zero-Hex).
  Native: Redix pool when `REDIS_CLIENT=native` (TLS via `REDIS_TLS=true`).
  """

  @default_timeout 5_000

  def native? do
    client =
      to_string(
        Laravex.Config.Repository.get("database.redis.client") ||
          System.get_env("REDIS_CLIENT") ||
          "phpredis"
      )

    client in ["native", "redix", "hex"]
  end

  def ping(opts \\ []) do
    case command(["PING"], opts) do
      {:ok, resp} -> resp
      other -> other
    end
  end

  def get(key, opts \\ []) do
    case command(["GET", key], opts) do
      {:ok, resp} -> resp
      other -> other
    end
  end

  def set(key, value, opts \\ []) do
    args =
      case Keyword.get(opts, :ex) do
        nil -> ["SET", key, value]
        seconds -> ["SETEX", key, to_string(seconds), value]
      end

    case command(args, Keyword.delete(opts, :ex)) do
      {:ok, _} -> :ok
      other -> other
    end
  end

  def del(key, opts \\ []) do
    case command(["DEL", key], opts) do
      {:ok, _} -> :ok
      other -> other
    end
  end

  def exists?(key, opts \\ []) do
    case command(["EXISTS", key], opts) do
      {:ok, n} -> n == 1
      _ -> false
    end
  end

  def lpush(key, value, opts \\ []) do
    case command(["LPUSH", key, value], opts) do
      {:ok, _} -> :ok
      other -> other
    end
  end

  def brpop(key, timeout \\ 1, opts \\ []) do
    case command(["BRPOP", key, to_string(timeout)], opts) do
      {:ok, [_queue, value]} -> {:ok, value}
      {:ok, nil} -> :error
      {:ok, _} -> :error
      _ -> :error
    end
  end

  def command(args, opts \\ []) when is_list(args) do
    if native?() do
      Laravex.Support.RedisPool.command(args, opts)
    else
      tcp_command(args, opts)
    end
  end

  def config(connection \\ "default") do
    cfg =
      Laravex.Config.Repository.get("database.redis.#{connection}") ||
        Laravex.Config.Repository.get("database.redis.default") ||
        %{}

    %{
      host: to_string(Map.get(cfg, "host", "127.0.0.1")),
      port: to_int(Map.get(cfg, "port", 6379)),
      password: Map.get(cfg, "password") || Map.get(cfg, :password),
      database: to_int(Map.get(cfg, "database", 0)),
      scheme: Map.get(cfg, "scheme") || System.get_env("REDIS_SCHEME"),
      timeout: @default_timeout
    }
  end

  # --- TCP (default) ---

  defp tcp_command(args, opts) do
    with {:ok, socket} <- connect(opts),
         {:ok, resp} <- tcp_send(socket, args),
         :ok <- close(socket) do
      {:ok, resp}
    end
  end

  def connect(opts) do
    cfg = Keyword.get(opts, :config) || config(Keyword.get(opts, :connection, "default"))
    host = Keyword.get(opts, :host, cfg.host)
    port = Keyword.get(opts, :port, cfg.port)
    timeout = Keyword.get(opts, :timeout, cfg.timeout)

    with {:ok, socket} <- :gen_tcp.connect(to_charlist(host), port, [:binary, active: false], timeout),
         :ok <- maybe_auth(socket, cfg.password),
         :ok <- maybe_select_db(socket, cfg.database) do
      {:ok, socket}
    end
  end

  defp tcp_send(socket, args) when is_list(args) do
    :ok = :gen_tcp.send(socket, encode_command(args))
    read_response(socket)
  end

  defp maybe_auth(_socket, nil), do: :ok
  defp maybe_auth(_socket, ""), do: :ok

  defp maybe_auth(socket, password) do
    case tcp_send(socket, ["AUTH", to_string(password)]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_select_db(_socket, db) when db in [0, "0", nil], do: :ok

  defp maybe_select_db(socket, db) do
    case tcp_send(socket, ["SELECT", to_string(db)]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp encode_command(args) do
    parts = Enum.map(args, &to_string/1)

    "*#{length(parts)}\r\n" <>
      Enum.map_join(parts, "", fn arg ->
        "$#{byte_size(arg)}\r\n#{arg}\r\n"
      end)
  end

  defp read_response(socket) do
    case recv_line(socket) do
      {:ok, "+" <> rest} ->
        {:ok, String.trim_trailing(rest, "\r")}

      {:ok, "-" <> rest} ->
        {:error, String.trim_trailing(rest, "\r")}

      {:ok, ":" <> rest} ->
        case Integer.parse(String.trim_trailing(rest, "\r")) do
          {n, _} -> {:ok, n}
          _ -> {:error, :invalid_integer}
        end

      {:ok, "$" <> rest} ->
        len = rest |> String.trim_trailing("\r") |> String.to_integer()

        if len < 0 do
          {:ok, nil}
        else
          {:ok, body} = recv_exact(socket, len + 2)
          {:ok, binary_part(body, 0, len)}
        end

      {:ok, "*" <> rest} ->
        count = rest |> String.trim_trailing("\r") |> String.to_integer()
        read_array(socket, count, [])

      {:error, _} = err ->
        err
    end
  end

  defp read_array(_socket, 0, acc), do: {:ok, Enum.reverse(acc)}

  defp read_array(socket, n, acc) do
    case read_response(socket) do
      {:ok, item} -> read_array(socket, n - 1, [item | acc])
      other -> other
    end
  end

  defp recv_line(socket), do: recv_line(socket, [])

  defp recv_line(socket, acc) do
    case :gen_tcp.recv(socket, 1, @default_timeout) do
      {:ok, "\n"} ->
        {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}

      {:ok, char} ->
        recv_line(socket, [char | acc])

      {:error, _} = err ->
        err
    end
  end

  defp recv_exact(socket, n), do: do_recv_exact(socket, n, "")

  defp do_recv_exact(_socket, n, acc) when byte_size(acc) >= n do
    <<got::binary-size(^n), _rest::binary>> = acc
    {:ok, got}
  end

  defp do_recv_exact(socket, n, acc) do
    need = n - byte_size(acc)

    case :gen_tcp.recv(socket, need, @default_timeout) do
      {:ok, more} -> do_recv_exact(socket, n, acc <> more)
      {:error, _} = err -> err
    end
  end

  defp close(socket) do
    _ = :gen_tcp.close(socket)
    :ok
  end

  defp to_int(n) when is_integer(n), do: n

  defp to_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      _ -> 0
    end
  end

  defp to_int(_), do: 0
end
