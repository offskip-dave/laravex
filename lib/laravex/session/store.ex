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

  def save(sid, session) when is_binary(sid) do
    ensure()
    driver = ensure_driver!()
    :ets.insert(@table, {sid, session})

    case driver do
      "database" -> persist_db(sid, session)
      "file" -> persist_file(sid, session)
    end

    :ok
  end

  def delete(sid) when is_binary(sid) do
    ensure()
    driver = ensure_driver!()
    :ets.delete(@table, sid)

    case driver do
      "database" -> delete_db(sid)
      "file" -> delete_file(sid)
    end

    :ok
  end

  def load(sid) do
    ensure()
    _ = ensure_driver!()

    case :ets.lookup(@table, sid) do
      [{^sid, session}] ->
        session

      [] ->
        case read_persistent(sid) do
          {:ok, session} ->
            :ets.insert(@table, {sid, session})
            session

          :error ->
            %{}
        end
    end
  end

  def cookie_name, do: Laravex.Config.Repository.get("session.cookie", "laravex-session")

  @supported_drivers ~w(file database)

  defp ensure_driver! do
    driver = to_string(Laravex.Config.Repository.get("session.driver", "file"))

    unless driver in @supported_drivers do
      raise ArgumentError,
            "Session uses unsupported driver #{inspect(driver)}. " <>
              "Supported drivers: #{Enum.join(@supported_drivers, ", ")} " <>
              "(set SESSION_DRIVER=file|database)."
    end

    driver
  end

  defp driver, do: ensure_driver!()

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

  defp read_persistent(sid) do
    case driver() do
      "database" -> read_db(sid)
      "file" -> read_file(sid)
    end
  end

  defp persist_file(sid, session) do
    dir = session_files_dir()
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, sid), :erlang.term_to_binary(session))
  end

  defp read_file(sid) do
    path = Path.join(session_files_dir(), sid)

    if File.exists?(path) do
      mtime = File.stat!(path).mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
      age = DateTime.diff(DateTime.utc_now(), mtime, :second)

      if age > lifetime_seconds() do
        _ = File.rm(path)
        :error
      else
        {:ok, :erlang.binary_to_term(File.read!(path))}
      end
    else
      :error
    end
  rescue
    _ -> :error
  end

  defp delete_file(sid) do
    path = Path.join(session_files_dir(), sid)
    _ = if File.exists?(path), do: File.rm(path)
    :ok
  end

  defp session_files_dir do
    Laravex.Config.Repository.get("session.files") ||
      Path.join(Laravex.Foundation.Application.base_path(), "storage/framework/sessions")
  end

  defp persist_db(sid, session) do
    if sessions_table?() do
      payload = session |> :erlang.term_to_binary() |> Base.encode64()
      now = System.system_time(:second)
      user_id = Map.get(session, "login_web")

      Laravex.Database.Connection.execute("DELETE FROM sessions WHERE id = ?", [sid])

      Laravex.Database.Connection.execute(
        "INSERT INTO sessions (id, user_id, payload, last_activity) VALUES (?, ?, ?, ?)",
        [sid, user_id, payload, now]
      )
    else
      persist_file(sid, session)
    end
  rescue
    _ -> persist_file(sid, session)
  end

  defp read_db(sid) do
    if sessions_table?() do
      case Laravex.Database.Connection.query(
             "SELECT payload, last_activity FROM sessions WHERE id = ?",
             [sid]
           ) do
        [%{"payload" => payload, "last_activity" => last}] ->
          last_i = to_int(last)

          if last_i > 0 and System.system_time(:second) - last_i > lifetime_seconds() do
            delete_db(sid)
            :error
          else
            {:ok, :erlang.binary_to_term(Base.decode64!(payload))}
          end

        _ ->
          :error
      end
    else
      read_file(sid)
    end
  rescue
    _ -> :error
  end

  defp delete_db(sid) do
    if sessions_table?() do
      Laravex.Database.Connection.execute("DELETE FROM sessions WHERE id = ?", [sid])
    end

    :ok
  rescue
    _ -> :ok
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

    case driver() do
      "database" ->
        if sessions_table?() do
          Laravex.Database.Connection.execute("DELETE FROM sessions WHERE last_activity < ?", [
            cutoff
          ])
        end

      "file" ->
        dir = session_files_dir()

        if File.dir?(dir) do
          Enum.each(File.ls!(dir), fn file ->
            path = Path.join(dir, file)

            with {:ok, stat} <- File.stat(path),
                 {:ok, mtime} <- NaiveDateTime.from_erl(stat.mtime),
                 {:ok, dt} <- DateTime.from_naive(mtime, "Etc/UTC") do
              if DateTime.diff(DateTime.utc_now(), dt, :second) > lifetime_seconds() do
                File.rm(path)
              end
            else
              _ -> :ok
            end
          end)
        end
    end
  end

  defp sessions_table? do
    Laravex.Database.Schema.has_table?("sessions")
  rescue
    _ -> false
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
