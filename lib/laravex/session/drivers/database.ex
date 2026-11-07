defmodule Laravex.Session.Drivers.Database do
  @moduledoc false
  @behaviour Laravex.Session.Driver

  @impl true
  def read(sid), do: read_db(sid)

  @impl true
  def write(sid, session) do
    if sessions_table?() do
      payload = session |> :erlang.term_to_binary() |> Base.encode64()
      now = System.system_time(:second)
      user_id = Map.get(session, "login_web")

      Laravex.Database.Connection.execute("DELETE FROM sessions WHERE id = ?", [sid])

      Laravex.Database.Connection.execute(
        "INSERT INTO sessions (id, user_id, payload, last_activity) VALUES (?, ?, ?, ?)",
        [sid, user_id, payload, now]
      )

      :ok
    else
      Laravex.Session.Drivers.File.write(sid, session)
    end
  rescue
    _ -> Laravex.Session.Drivers.File.write(sid, session)
  end

  @impl true
  def delete(sid) do
    if sessions_table?() do
      Laravex.Database.Connection.execute("DELETE FROM sessions WHERE id = ?", [sid])
    end

    :ok
  rescue
    _ -> :ok
  end

  @impl true
  def gc_expired(cutoff) do
    if sessions_table?() do
      Laravex.Database.Connection.execute("DELETE FROM sessions WHERE last_activity < ?", [cutoff])
    end

    :ok
  end

  defp lifetime_seconds do
    case Laravex.Config.Repository.get("session.lifetime", 120) do
      n when is_integer(n) -> n * 60
      n when is_binary(n) -> String.to_integer(n) * 60
      _ -> 120 * 60
    end
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
            delete(sid)
            :error
          else
            {:ok, :erlang.binary_to_term(Base.decode64!(payload))}
          end

        _ ->
          :error
      end
    else
      Laravex.Session.Drivers.File.read(sid)
    end
  rescue
    _ -> :error
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
