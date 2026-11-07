defmodule Laravex.Http.CookieJar do
  @moduledoc "Process-local queued cookies (Laravel Cookie::queue)."

  @key :laravex_queued_cookies

  def queue(name, value, opts \\ []) do
    Process.put(@key, queued() ++ [{to_string(name), value, opts}])
    :ok
  end

  @doc "Queue a long-lived cookie (~400 days, Laravel `Cookie::forever`)."
  def forever(name, value, opts \\ []) do
    opts = Keyword.put_new(opts, :max_age, 576_000 * 60)
    queue(name, value, opts)
  end

  def queued, do: Process.get(@key, [])

  @doc "Remove a cookie from the queue without emitting a Set-Cookie (Laravel `unqueue`)."
  def unqueue(name) do
    Process.put(
      @key,
      Enum.reject(queued(), fn {n, _, _} -> n == to_string(name) end)
    )

    :ok
  end

  @doc "Queue a deletion cookie (Max-Age=0)."
  def expire(name, opts \\ []) do
    _ = unqueue(name)
    queue(name, "", Keyword.merge(opts, max_age: 0))
  end

  @doc "Expire a cookie (Laravel `Cookie::forget`)."
  def forget(name, opts \\ []), do: expire(name, opts)

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
