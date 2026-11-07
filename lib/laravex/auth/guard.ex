defmodule Laravex.Auth.Guard do
  @moduledoc "Session authentication guard."

  def attempt(credentials, request) when is_map(credentials) do
    email = credentials["email"] || credentials[:email]
    password = credentials["password"] || credentials[:password]
    model = Laravex.Config.Repository.get("auth.providers.users.model", App.Models.User)

    case model.find_by_email(email) do
      nil ->
        {:error, :invalid}

      user ->
        if Laravex.Hashing.Hash.check(password, user.password) do
          request = login(user, request)
          {:ok, user, request}
        else
          {:error, :invalid}
        end
    end
  end

  def login(user, request) do
    request
    |> Laravex.Session.Store.regenerate()
    |> Laravex.Session.Store.put("login_web", user.id)
    |> Map.put(:user, user)
  end

  def logout(request) do
    request
    |> Laravex.Session.Store.put("login_web", nil)
    |> Laravex.Session.Store.regenerate()
    |> Map.put(:user, nil)
  end

  def user(%{user: %{} = user}), do: user

  def user(%{session: session}) do
    case Process.get(:laravex_acting_as) do
      %{id: _} = acting ->
        acting

      _ ->
        case Map.get(session, "login_web") do
          nil ->
            nil

          id ->
            model = Laravex.Config.Repository.get("auth.providers.users.model", App.Models.User)
            model.find(id)
        end
    end
  end

  def user(_), do: Process.get(:laravex_acting_as)

  def check?(request), do: user(request) != nil

  def id(request) do
    case user(request) do
      %{id: id} -> id
      _ -> nil
    end
  end

  def authorize(user, ability, resource \\ nil) do
    Laravex.Auth.Gate.allows?(user, ability, resource)
  end
end

defmodule Laravex.Auth.Gate do
  @moduledoc "Simple policy/gate registry."

  @table :laravex_gates

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

  def define(ability, fun) when is_atom(ability) or is_binary(ability) do
    ensure()
    :ets.insert(@table, {to_string(ability), fun})
    :ok
  end

  def allows?(user, ability, resource \\ nil) do
    ensure()

    case :ets.lookup(@table, to_string(ability)) do
      [{_, fun}] when is_function(fun, 2) -> fun.(user, resource)
      [{_, fun}] when is_function(fun, 1) -> fun.(user)
      [] -> false
    end
  end
end

defmodule Laravex.Auth.Token do
  @moduledoc "Simple API token store (Sanctum-like subset)."

  @table :laravex_api_tokens

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

  def create(user, name \\ "default") do
    ensure()
    plain = Laravex.Support.Helpers.str_random(40)
    hash = :crypto.hash(:sha256, plain) |> Base.encode16(case: :lower)
    :ets.insert(@table, {hash, %{user_id: user.id, name: name}})
    %{"plainTextToken" => plain, "accessToken" => hash}
  end

  def find_user(plain_token) when is_binary(plain_token) do
    ensure()
    hash = :crypto.hash(:sha256, plain_token) |> Base.encode16(case: :lower)

    case :ets.lookup(@table, hash) do
      [{_, %{user_id: id}}] ->
        model = Laravex.Config.Repository.get("auth.providers.users.model", App.Models.User)
        model.find(id)

      _ ->
        nil
    end
  end
end
