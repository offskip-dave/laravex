defmodule Laravex.Http.Server do
  @moduledoc """
  Minimal HTTP/1.1 server using gen_tcp (no external packages).
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

  def handle_raw(data) do
    case parse_request(data) do
      {:ok, request} ->
        Laravex.Foundation.Application.handle_request(request)

      {:error, _} ->
        Laravex.Http.Response.new(400, "Bad Request", [
          {"content-type", "text/plain; charset=utf-8"}
        ])
    end
  end

  defp accept_loop(listen) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        spawn(fn -> serve(socket) end)
        accept_loop(listen)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        accept_loop(listen)
    end
  end

  defp serve(socket) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, data} ->
        response = handle_raw(data)
        :gen_tcp.send(socket, Laravex.Http.Response.to_iodata(response))
        :gen_tcp.close(socket)

      {:error, _} ->
        :gen_tcp.close(socket)
    end
  end

  defp parse_request(data) do
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

                {:ok, Laravex.Http.Request.capture(method, path, headers, body)}

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
