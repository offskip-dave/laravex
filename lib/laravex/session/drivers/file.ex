defmodule Laravex.Session.Drivers.File do
  @moduledoc false
  @behaviour Laravex.Session.Driver

  @impl true
  def read(sid), do: read_file(sid)

  @impl true
  def write(sid, session), do: persist_file(sid, session)

  @impl true
  def delete(sid), do: delete_file(sid)

  @impl true
  def gc_expired(_cutoff), do: gc_files()

  defp lifetime_seconds do
    case Laravex.Config.Repository.get("session.lifetime", 120) do
      n when is_integer(n) -> n * 60
      n when is_binary(n) -> String.to_integer(n) * 60
      _ -> 120 * 60
    end
  end

  defp session_files_dir do
    Laravex.Config.Repository.get("session.files") ||
      Path.join(Laravex.Foundation.Application.base_path(), "storage/framework/sessions")
  end

  defp persist_file(sid, session) do
    dir = session_files_dir()
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, sid), :erlang.term_to_binary(session))
    :ok
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

  defp gc_files do
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

    :ok
  end
end
