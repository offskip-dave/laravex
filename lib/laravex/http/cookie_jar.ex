defmodule Laravex.Http.CookieJar do
  @moduledoc "Process-local queued cookies (Laravel Cookie::queue)."

  @key :laravex_queued_cookies

  def queue(name, value, opts \\ []) do
    Process.put(@key, queued() ++ [{to_string(name), value, opts}])
    :ok
  end

  def queued, do: Process.get(@key, [])

  def forget(name) do
    Process.put(
      @key,
      Enum.reject(queued(), fn {n, _, _} -> n == to_string(name) end)
    )

    :ok
  end

  def clear do
    Process.delete(@key)
    :ok
  end

  def apply(%Laravex.Http.Response{} = response) do
    Enum.reduce(queued(), response, fn {name, value, opts}, resp ->
      Laravex.Http.Response.with_cookie(resp, name, value, opts)
    end)
  end
end

defmodule Laravex.Http.Middleware.AddQueuedCookies do
  @moduledoc "Flush CookieJar onto the response before EncryptCookies terminates."

  def handle(request, _opts), do: {:ok, request}

  def terminate(_request, %Laravex.Http.Response{} = response) do
    Laravex.Http.CookieJar.apply(response)
  end
end
