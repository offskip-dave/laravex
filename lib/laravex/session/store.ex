defmodule Laravex.Session.Store do
  @moduledoc """
  Session store with `file` and `database` drivers (Laravel session).

  ETS is always used as a request-local cache; persistence follows `session.driver`.
  """

  @table :laravex_sessions

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

  def start(request) do
    ensure()
    cookie = Laravex.Config.Repository.get("session.cookie", "laravex-session")
    sid = Map.get(request.cookies, cookie) || Laravex.Support.Helpers.str_random(40)
    session = load(sid)
    maybe_lottery_gc()
    %{request | session_id: sid, session: session}
  end

  def get(request_or_sid, key, default \\ nil)

  def get(%{session: session}, key, default), do: Map.get(session, to_string(key), default)

  def get(sid, key, default) when is_binary(sid) do
    load(sid) |> Map.get(to_string(key), default)
  end

  def put(%{session: session} = request, key, value) do
    %{request | session: Map.put(session, to_string(key), value)}
  end

  def forget(%{session: session} = request, key) do
    %{request | session: Map.delete(session, to_string(key))}
  end

  @doc "Get a value and remove it from the session (Laravel `session()->pull`)."
  def pull(request, key, default \\ nil)

  def pull(%{session: session} = request, key, default) do
    k = to_string(key)
    value = Map.get(session, k, default)
    {value, %{request | session: Map.delete(session, k)}}
  end

  def all(%{session: session}), do: session

  def only(%{session: session}, keys) when is_list(keys) do
    keys = Enum.map(keys, &to_string/1)
    Map.take(session, keys)
  end

  @doc "Previous request URL stored by the HTTP kernel (Laravel `previousUrl`)."
  def previous_url(request_or_session, fallback \\ nil)

  def previous_url(%{session: session}, fallback), do: previous_url(session, fallback)

  def previous_url(session, fallback) when is_map(session) do
    Map.get(session, "_previous.url", fallback)
  end

  @doc "Flash data for the *next* request (Laravel session()->flash)."
  def flash(request, key, value) do
    bag = flash_bag(request.session)
    new = Map.put(bag["new"] || %{}, to_string(key), value)
    put(request, "_flash", %{"old" => bag["old"] || %{}, "new" => new})
  end

  @doc "Flash data for the *current* request only (Laravel session()->now)."
  def flash_now(request, key, value) do
    now = Process.get(:laravex_flash_now, %{})
    Process.put(:laravex_flash_now, Map.put(now, to_string(key), value))
    flash = Map.merge(request.flash || %{}, %{to_string(key) => value})
    %{request | flash: flash}
  end

  @doc "Keep selected flash keys for another request (Laravel `keep`)."
  def keep(%{session: session} = request, keys) when is_list(keys) do
    bag = flash_bag(session)
    old = bag["old"] || %{}
    keys = Enum.map(keys, &to_string/1)
    kept = Map.take(old, keys)
    new = Map.merge(bag["new"] || %{}, kept)
    put(request, "_flash", %{"old" => old, "new" => new})
  end

  @doc "Keep all current flash for another request (Laravel `reflash`)."
  def reflash(%{session: session} = request) do
    bag = flash_bag(session)
    old = bag["old"] || %{}
    new = Map.merge(bag["new"] || %{}, old)
    put(request, "_flash", %{"old" => old, "new" => new})
  end

  def flash_bag(session) when is_map(session) do
    case Map.get(session, "_flash") do
      %{"old" => _, "new" => _} = bag ->
        bag

      bag when is_map(bag) ->
        %{"old" => %{}, "new" => stringify_map(bag)}

      _ ->
        # Legacy `_flash.key` entries
        legacy =
          session
          |> Enum.filter(fn {k, _} -> String.starts_with?(to_string(k), "_flash.") end)
          |> Map.new(fn {k, v} -> {String.trim_leading(to_string(k), "_flash."), v} end)

        %{"old" => %{}, "new" => legacy}
    end
  end

  def age_flash(session) when is_map(session) do
    bag = flash_bag(session)
    # Consume: previous new becomes old; clear new for this request's outgoing flashes.
    aged = %{"old" => bag["new"] || %{}, "new" => %{}}

    session
    |> Enum.reject(fn {k, _} -> String.starts_with?(to_string(k), "_flash.") end)
    |> Map.new()
    |> Map.put("_flash", aged)
  end

  def regenerate(%{session_id: old, session: session} = request) do
    new_id = Laravex.Support.Helpers.str_random(40)
    save(new_id, session)
    if is_binary(old), do: delete(old)
    %{request | session_id: new_id}
  end

  @doc "Clear all session data but keep the id (Laravel `flush`)."
  def flush(%{session: _} = request) do
    %{request | session: %{}, flash: %{}}
  end

  @doc "Flush session data and regenerate the id (Laravel `invalidate`)."
  def invalidate(request) do
    request
    |> flush()
    |> regenerate()
  end

  def save(sid, session) when is_binary(sid) do
    ensure()
    _ = session_driver()
    :ets.insert(@table, {sid, session})
    session_driver().write(sid, session)
    :ok
  end

  def delete(sid) when is_binary(sid) do
    ensure()
    _ = session_driver()
    :ets.delete(@table, sid)
    session_driver().delete(sid)
    :ok
  end

  def load(sid) do
    ensure()
    _ = session_driver()

    case :ets.lookup(@table, sid) do
      [{^sid, session}] ->
        session

      [] ->
        case session_driver().read(sid) do
          {:ok, session} ->
            :ets.insert(@table, {sid, session})
            session

          :error ->
            %{}
        end
    end
  end

  def cookie_name, do: Laravex.Config.Repository.get("session.cookie", "laravex-session")

  defp session_driver, do: Laravex.Session.Resolver.module()

  defp stringify_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp lifetime_seconds do
    case Laravex.Config.Repository.get("session.lifetime", 120) do
      n when is_integer(n) -> n * 60
      n when is_binary(n) -> String.to_integer(n) * 60
      _ -> 120 * 60
    end
  end

  defp maybe_lottery_gc do
    {odds, total} = lottery()

    if total > 0 and :rand.uniform(total) <= odds do
      gc_expired()
    end
  rescue
    _ -> :ok
  end

  defp lottery do
    case Laravex.Config.Repository.get("session.lottery", [2, 100]) do
      [a, b] -> {to_int(a), to_int(b)}
      _ -> {2, 100}
    end
  end

  defp gc_expired do
    cutoff = System.system_time(:second) - lifetime_seconds()
    session_driver().gc_expired(cutoff)
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

defmodule Laravex.Http.Middleware.StartSession do
  def handle(request, _opts) do
    request = Laravex.Session.Store.start(request)
    user = Laravex.Auth.Guard.user(request)
    {:ok, %{request | user: user}}
  end
end

defmodule Laravex.Http.Middleware.VerifyCsrfToken do
  @moduledoc "CSRF verification for state-changing requests."

  def handle(%{method: method} = request, _opts) when method in ["GET", "HEAD", "OPTIONS"] do
    token = Map.get(request.session, "_token") || Laravex.Support.Helpers.str_random(40)
    request = Laravex.Session.Store.put(request, "_token", token)
    {:ok, request}
  end

  def handle(request, _opts) do
    except = csrf_except()

    if request.path in except do
      {:ok, request}
    else
      session_token = Map.get(request.session, "_token")

      request_token =
        Laravex.Http.Request.input(request, "_token") ||
          Laravex.Http.Request.header(request, "x-csrf-token") ||
          Laravex.Http.Request.header(request, "x-xsrf-token")

      if session_token && request_token && secure_compare(session_token, request_token) do
        {:ok, request}
      else
        {:halt, Laravex.Http.Response.html("CSRF token mismatch.", 419)}
      end
    end
  end

  defp csrf_except do
    configured = Application.get_env(:laravex, :csrf_except, [])
    ["/", "/up"] ++ List.wrap(configured)
  end

  defp secure_compare(a, b) do
    a = to_string(a)
    b = to_string(b)
    byte_size(a) == byte_size(b) and :crypto.hash_equals(a, b)
  end
end
