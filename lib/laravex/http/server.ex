defmodule Laravex.Http.Server do
  @moduledoc """
  Minimal HTTP/1.1 server using gen_tcp. Serves public/ static files before app routing.
  """

  require Logger

  def start_link(opts) do
    port = Keyword.get(opts, :port, 8000)
    {:ok, listen} = :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])
    {:ok, actual_port} = :inet.port(listen)
    Logger.info("Laravex HTTP server listening on http://127.0.0.1:#{actual_port}")
    pid = spawn_link(fn -> accept_loop(listen) end)
    {:ok, pid, actual_port}
  end

  def handle_raw(data, opts \\ []) do
    case parse_request(data, opts) do
      {:ok, request} ->
        if request.peer, do: Process.put(:laravex_peer, request.peer)

        case try_static(request) do
          {:ok, response} -> response
          :miss -> Laravex.Foundation.Application.handle_request(request)
        end

      {:error, _} ->
        Laravex.Http.Response.new(400, "Bad Request", [
          {"content-type", "text/plain; charset=utf-8"}
        ])
    end
  end

  defp try_static(%{method: method, path: path}) when method in ["GET", "HEAD"] do
    rel =
      path
      |> URI.decode()
      |> String.split("?", parts: 2)
      |> hd()
      |> String.trim_leading("/")

    if rel == "" or String.contains?(rel, "..") do
      :miss
    else
      full = Path.join(Laravex.Foundation.Application.base_path(), Path.join("public", rel))

      if File.regular?(full) do
        body = File.read!(full)
        {:ok, Laravex.Http.Response.new(200, body, [{"content-type", mime(full)}])}
      else
        :miss
      end
    end
  end

  defp try_static(_), do: :miss

  defp mime(path) do
    case Path.extname(path) do
      ".html" -> "text/html; charset=utf-8"
      ".css" -> "text/css; charset=utf-8"
      ".js" -> "application/javascript; charset=utf-8"
      ".json" -> "application/json; charset=utf-8"
      ".svg" -> "image/svg+xml"
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".ico" -> "image/x-icon"
      ".txt" -> "text/plain; charset=utf-8"
      ".woff" -> "font/woff"
      ".woff2" -> "font/woff2"
      _ -> "application/octet-stream"
    end
  end

  defp accept_loop(listen) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        spawn(fn -> serve(socket) end)
        accept_loop(listen)

      {:error, :closed} ->
        :ok

      {:error, _} ->
        accept_loop(listen)
    end
  end

  defp serve(socket) do
    peer = peername(socket)

    case recv_all(socket) do
      {:ok, data} ->
        response = handle_raw(data, peer: peer)
        :gen_tcp.send(socket, Laravex.Http.Response.to_iodata(response))
        :gen_tcp.close(socket)

      {:error, _} ->
        :gen_tcp.close(socket)
    end
  end

  defp peername(socket) do
    case :inet.peername(socket) do
      {:ok, {ip, _port}} -> ip |> :inet.ntoa() |> to_string()
      _ -> nil
    end
  end

  defp recv_all(socket, acc \\ "") do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, data} ->
        acc = acc <> data

        case content_complete?(acc) do
          true -> {:ok, acc}
          false -> recv_all(socket, acc)
        end

      {:error, :timeout} when acc != "" ->
        {:ok, acc}

      {:error, reason} ->
        if acc == "", do: {:error, reason}, else: {:ok, acc}
    end
  end

  defp content_complete?(data) do
    case String.split(data, "\r\n\r\n", parts: 2) do
      [_headers, body] ->
        cl =
          case Regex.run(~r/content-length:\s*(\d+)/i, data) do
            [_, n] -> String.to_integer(n)
            _ -> 0
          end

        byte_size(body) >= cl

      _ ->
        false
    end
  end

  defp parse_request(data, opts) do
    case String.split(data, "\r\n\r\n", parts: 2) do
      [header_block | rest] ->
        body = List.first(rest) || ""
        lines = String.split(header_block, "\r\n")

        case lines do
          [request_line | header_lines] ->
            case String.split(request_line, " ") do
              [method, path | _] ->
                headers =
                  header_lines
                  |> Enum.map(fn line ->
                    case String.split(line, ":", parts: 2) do
                      [k, v] -> {String.trim(k), String.trim(v)}
                      _ -> nil
                    end
                  end)
                  |> Enum.reject(&is_nil/1)
                  |> Map.new()

                {:ok, Laravex.Http.Request.capture(method, path, headers, body, opts)}

              _ ->
                {:error, :bad_request_line}
            end

          _ ->
            {:error, :empty}
        end

      _ ->
        {:error, :malformed}
    end
  end
end
