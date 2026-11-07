defmodule Laravex.Http.RateLimiter do
  @moduledoc """
  Named rate limiters (Laravel RateLimiter::for) plus attempt/hit helpers.

      Laravex.Http.RateLimiter.for("api", fn _request -> [max: 60, decay: 1] end)

      RateLimiter.attempt("login:" <> email, 5, 60, fn -> do_login() end)
  """

  @table :laravex_rate_limiters

  def ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        _ = :ets.new(@table, [:named_table, :public, :set])
        :ok
      rescue
        ArgumentError -> :ok
      end
    else
      :ok
    end
  end

  def for(name, fun) when is_function(fun, 0) or is_function(fun, 1) do
    ensure()
    :ets.insert(@table, {to_string(name), fun})
    :ok
  end

  def get(name) do
    ensure()

    case :ets.lookup(@table, to_string(name)) do
      [{_, fun}] -> fun
      [] -> nil
    end
  end

  def resolve(name, request \\ nil) do
    case get(name) do
      nil ->
        [max: 60, decay: 1]

      fun when is_function(fun, 0) ->
        normalize(fun.())

      fun when is_function(fun, 1) ->
        normalize(fun.(request))
    end
  end

  @doc "Current hit count for `key`."
  def hits(key), do: Laravex.Cache.Manager.get(cache_key(key)) || 0

  @doc "Whether `key` has exceeded `max_attempts`."
  def too_many_attempts?(key, max_attempts) when is_integer(max_attempts) do
    hits(key) >= max_attempts
  end

  @doc "Attempts remaining before lockout."
  def remaining(key, max_attempts) when is_integer(max_attempts) do
    max(max_attempts - hits(key), 0)
  end

  @doc "Seconds until the limiter window for `key` expires (best-effort via cache TTL metadata)."
  def available_in(key) do
    case Laravex.Cache.Manager.get("_ttl:" <> cache_key(key)) do
      ts when is_integer(ts) ->
        max(ts - System.system_time(:second), 0)

      _ ->
        0
    end
  end

  @doc "Increment hits for `key` (decay in seconds)."
  def hit(key, decay_seconds \\ 60) when is_integer(decay_seconds) do
    ck = cache_key(key)
    count = hits(key) + 1
    Laravex.Cache.Manager.put(ck, count, decay_seconds)
    expires = System.system_time(:second) + decay_seconds
    Laravex.Cache.Manager.put("_ttl:" <> ck, expires, decay_seconds)
    count
  end

  def clear(key) do
    ck = cache_key(key)
    Laravex.Cache.Manager.forget(ck)
    Laravex.Cache.Manager.forget("_ttl:" <> ck)
    :ok
  end

  @doc """
  Run `fun` if under `max_attempts`, otherwise return `{:error, :too_many_attempts}`.

  On success returns `{:ok, result}` and increments the hit counter.
  """
  def attempt(key, max_attempts, decay_seconds \\ 60, fun)
      when is_integer(max_attempts) and is_integer(decay_seconds) and is_function(fun, 0) do
    if too_many_attempts?(key, max_attempts) do
      {:error, :too_many_attempts}
    else
      result = fun.()
      _ = hit(key, decay_seconds)
      {:ok, result}
    end
  end

  defp cache_key(key), do: "rate:" <> to_string(key)

  defp normalize(opts) when is_list(opts), do: opts
  defp normalize(%{max: max, decay: decay}), do: [max: max, decay: decay]
  defp normalize(%{"max" => max, "decay" => decay}), do: [max: max, decay: decay]
  defp normalize(_), do: [max: 60, decay: 1]
end
