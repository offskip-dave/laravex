defmodule Laravex.Http.Response do
  @moduledoc false

  defstruct status: 200, body: "", headers: []

  def new(status, body, headers \\ []) do
    %__MODULE__{status: status, body: to_string(body), headers: headers}
  end

  def html(body, status \\ 200) do
    new(status, body, [{"content-type", "text/html; charset=utf-8"}])
  end

  def to_iodata(%__MODULE__{} = response) do
    reason = reason_phrase(response.status)
    header_lines =
      (response.headers ++ [{"content-length", Integer.to_string(byte_size(response.body))}])
      |> Enum.map(fn {k, v} -> "#{k}: #{v}\r\n" end)

    [
      "HTTP/1.1 #{response.status} #{reason}\r\n",
      header_lines,
      "connection: close\r\n",
      "\r\n",
      response.body
    ]
  end

  defp reason_phrase(200), do: "OK"
  defp reason_phrase(404), do: "Not Found"
  defp reason_phrase(500), do: "Internal Server Error"
  defp reason_phrase(_), do: "OK"
end
