defmodule Laravex.Session.Drivers.Cookie do
  @moduledoc """
  Cookie session driver — entire payload encrypted into the session cookie.
  Max ~4KB after encryption (browser cookie limits).
  """
  @behaviour Laravex.Session.Driver

  @max_bytes 3800
  @payload_key :laravex_cookie_session_payload

  @impl true
  def read(sid) do
    case Process.get({@payload_key, sid}) do
      %{} = session -> {:ok, session}
      _ -> {:ok, %{}}
    end
  end

  @impl true
  def write(sid, session) when is_map(session) do
    Process.put({@payload_key, sid}, session)
    :ok
  end

  @impl true
  def delete(sid) do
    Process.delete({@payload_key, sid})
    :ok
  end

  @impl true
  def gc_expired(_cutoff), do: :ok

  @doc "Seal session map into an encrypted cookie value."
  def seal(session) when is_map(session) do
    json = Laravex.Support.JSON.encode!(session)
    sealed = Laravex.Encryption.Crypt.encrypt(json)

    if byte_size(sealed) > @max_bytes do
      raise ArgumentError,
            "Cookie session payload too large (#{byte_size(sealed)} bytes). Keep under ~4KB."
    end

    sealed
  end

  @doc "Open encrypted cookie value into a session map."
  def open(nil), do: %{}
  def open(""), do: %{}

  def open(payload) when is_binary(payload) do
    case Laravex.Encryption.Crypt.decrypt(payload) do
      bin when is_binary(bin) ->
        case Laravex.Support.JSON.decode(bin) do
          {:ok, %{} = map} -> map
          _ -> %{}
        end

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end
end
