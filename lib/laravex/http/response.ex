defmodule Laravex.Http.Response do
  @moduledoc false

  defstruct status: 200, body: "", headers: [], cookies: []

  def new(status, body, headers \\ []) do
    %__MODULE__{status: status, body: to_string(body), headers: headers}
  end

  def html(body, status \\ 200) do
    new(status, body, [{"content-type", "text/html; charset=utf-8"}])
  end

  def json(data, status \\ 200) do
    new(status, Laravex.Support.JSON.encode!(stringify(data)), [
      {"content-type", "application/json; charset=utf-8"}
    ])
  end

  @doc """
  Laravel LengthAwarePaginator-shaped JSON envelope.
  `mapper` transforms each item in `page.data`.
  """
  def json_paginated(page, mapper \\ & &1, status \\ 200) when is_map(page) do
    data = Map.get(page, :data) || Map.get(page, "data") || []
    total = Map.get(page, :total) || Map.get(page, "total") || 0
    per_page = Map.get(page, :per_page) || Map.get(page, "per_page") || 15
    current = Laravex.Http.Paginator.current_page(page)
    last = Laravex.Http.Paginator.last_page(page)
    path = Laravex.Http.Paginator.pager_path(page)

    json(
      %{
        data: Enum.map(List.wrap(data), mapper),
        links: %{
          first: Laravex.Http.Paginator.page_url(page, 1, path),
          last: Laravex.Http.Paginator.page_url(page, last, path),
          prev: if(current > 1, do: Laravex.Http.Paginator.page_url(page, current - 1, path), else: nil),
          next: if(current < last, do: Laravex.Http.Paginator.page_url(page, current + 1, path), else: nil)
        },
        meta: %{
          current_page: current,
          from: if(total == 0, do: nil, else: (current - 1) * per_page + 1),
          last_page: last,
          path: path,
          per_page: per_page,
          to: min(current * per_page, total),
          total: total
        }
      },
      status
    )
  end

  def redirect(to, status \\ 302) do
    new(status, "", [{"location", to}])
  end

  def with_cookie(%__MODULE__{} = resp, name, value, opts \\ []) do
    max_age = Keyword.get(opts, :max_age)
    path = Keyword.get(opts, :path, "/")
    http_only = Keyword.get(opts, :http_only, true)

    cookie =
      "#{name}=#{URI.encode(to_string(value))}; Path=#{path}" <>
        if(http_only, do: "; HttpOnly", else: "") <>
        if(max_age, do: "; Max-Age=#{max_age}", else: "")

    %{resp | cookies: resp.cookies ++ [cookie]}
  end

  def to_iodata(%__MODULE__{} = response) do
    reason = reason_phrase(response.status)

    set_cookies = Enum.map(response.cookies, fn c -> {"set-cookie", c} end)

    headers =
      (response.headers ++ set_cookies ++ [{"content-length", Integer.to_string(byte_size(response.body))}])
      |> Enum.map(fn {k, v} -> "#{k}: #{v}\r\n" end)

    [
      "HTTP/1.1 #{response.status} #{reason}\r\n",
      headers,
      "connection: close\r\n",
      "\r\n",
      response.body
    ]
  end

  defp stringify(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify(other), do: %{"data" => inspect(other)}

  defp reason_phrase(200), do: "OK"
  defp reason_phrase(201), do: "Created"
  defp reason_phrase(204), do: "No Content"
  defp reason_phrase(302), do: "Found"
  defp reason_phrase(400), do: "Bad Request"
  defp reason_phrase(401), do: "Unauthorized"
  defp reason_phrase(403), do: "Forbidden"
  defp reason_phrase(404), do: "Not Found"
  defp reason_phrase(419), do: "Page Expired"
  defp reason_phrase(422), do: "Unprocessable Entity"
  defp reason_phrase(429), do: "Too Many Requests"
  defp reason_phrase(500), do: "Internal Server Error"
  defp reason_phrase(_), do: "OK"
end
