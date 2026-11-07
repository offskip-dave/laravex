defmodule Laravex.Session.Store do
  @moduledoc "File/database-backed session store (file driver by default for simplicity)."

  @table :laravex_sessions

  def ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        :ets.new(@table, [:named_table, :public, :set])
      rescue
        ArgumentError -> :ok
      end
    end

    :ok
  end

  def start(request) do
    ensure()
    cookie = Laravex.Config.Repository.get("session.cookie", "laravex-session")
    sid = Map.get(request.cookies, cookie) || Laravex.Support.Helpers.str_random(40)
    session = load(sid)
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

  def flash(request, key, value) do
    put(request, "_flash." <> to_string(key), value)
  end

  def regenerate(%{session_id: old, session: session} = request) do
    new_id = Laravex.Support.Helpers.str_random(40)
    # Carry session data to the new id
    save(new_id, session)
    if is_binary(old), do: delete(old)
    %{request | session_id: new_id}
  end

  def save(sid, session) when is_binary(sid) do
    ensure()
    :ets.insert(@table, {sid, session})
    persist_file(sid, session)
    :ok
  end

  def delete(sid) when is_binary(sid) do
    ensure()
    :ets.delete(@table, sid)
    path = Path.join(Laravex.Foundation.Application.base_path(), "storage/framework/sessions/#{sid}")
    if File.exists?(path), do: File.rm(path)
    :ok
  end

  def load(sid) do
    ensure()

    case :ets.lookup(@table, sid) do
      [{^sid, session}] ->
        session

      [] ->
        case read_file(sid) do
          {:ok, session} ->
            :ets.insert(@table, {sid, session})
            session

          :error ->
            %{}
        end
    end
  end

  def cookie_name, do: Laravex.Config.Repository.get("session.cookie", "laravex-session")

  defp persist_file(sid, session) do
    dir = Path.join(Laravex.Foundation.Application.base_path(), "storage/framework/sessions")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, sid), :erlang.term_to_binary(session))
  end

  defp read_file(sid) do
    path = Path.join(Laravex.Foundation.Application.base_path(), "storage/framework/sessions/#{sid}")

    if File.exists?(path) do
      {:ok, :erlang.binary_to_term(File.read!(path))}
    else
      :error
    end
  end
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
