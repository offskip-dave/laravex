defmodule Laravex.Auth.Guard do
  @moduledoc "Session authentication guard with remember-me and rehash-on-login."

  @remember_cookie "remember_web"

  def attempt(credentials, request) when is_map(credentials) do
    email = credentials["email"] || credentials[:email]
    password = credentials["password"] || credentials[:password]
    remember? = truthy?(credentials["remember"] || credentials[:remember])
    model = Laravex.Config.Repository.get("auth.providers.users.model", App.Models.User)

    case model.find_by_email(email) do
      nil ->
        {:error, :invalid}

      user ->
        if Laravex.Hashing.Hash.check(password, user.password) do
          user = maybe_rehash(user, password, model)
          request = login(user, request, remember: remember?)
          {:ok, user, request}
        else
          {:error, :invalid}
        end
    end
  end

  def login(user, request, opts \\ []) do
    remember? = Keyword.get(opts, :remember, false)

    request =
      request
      |> Laravex.Session.Store.regenerate()
      |> Laravex.Session.Store.put("login_web", user.id)
      |> Map.put(:user, user)

    if remember?, do: issue_remember_cookie(user, request), else: request
  end

  def logout(request) do
    user = user(request)

    if user && Map.get(user, :remember_token) do
      model = Laravex.Config.Repository.get("auth.providers.users.model", App.Models.User)
      model.save(%{user | remember_token: nil})
    end

    request
    |> Laravex.Session.Store.put("login_web", nil)
    |> Laravex.Session.Store.regenerate()
    |> clear_remember_cookie()
    |> Map.put(:user, nil)
  end

  def user(%{user: %{} = user}), do: user

  def user(%{session: session} = request) do
    case Process.get(:laravex_acting_as) do
      %{id: _} = acting ->
        acting

      _ ->
        case Map.get(session, "login_web") do
          nil ->
            via_remember(request)

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
    Laravex.Auth.Gate.authorize(user, ability, resource)
  end

  def allows?(user, ability, resource \\ nil) do
    Laravex.Auth.Gate.allows?(user, ability, resource)
  end

  def denies?(user, ability, resource \\ nil), do: not allows?(user, ability, resource)

  def remember_cookie_name, do: @remember_cookie

  defp maybe_rehash(user, password, model) do
    if Laravex.Hashing.Hash.needs_rehash?(user.password) do
      model.save(%{user | password: Laravex.Hashing.Hash.make(password)})
    else
      user
    end
  end

  defp via_remember(request) do
    case Map.get(request.cookies || %{}, @remember_cookie) do
      nil ->
        nil

      raw ->
        case decode_remember(raw) do
          {id, token} ->
            model = Laravex.Config.Repository.get("auth.providers.users.model", App.Models.User)

            case model.find(id) do
              %{remember_token: ^token} = user when is_binary(token) and token != "" ->
                user

              _ ->
                nil
            end

          _ ->
            nil
        end
    end
  end

  defp issue_remember_cookie(user, request) do
    model = Laravex.Config.Repository.get("auth.providers.users.model", App.Models.User)
    token = Laravex.Support.Helpers.str_random(60)
    user = model.save(%{user | remember_token: token})
    value = encode_remember(user.id, token)
    Process.put(:laravex_remember_cookie, {value, true})
    %{request | user: user}
  end

  defp clear_remember_cookie(request) do
    Process.put(:laravex_remember_cookie, {"", false})
    request
  end

  defp encode_remember(id, token) do
    Base.encode64("#{id}|#{token}")
  end

  defp decode_remember(raw) do
    case Base.decode64(to_string(raw)) do
      {:ok, decoded} ->
        case String.split(decoded, "|", parts: 2) do
          [id, token] -> {id, token}
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp truthy?(v), do: v in [true, "true", "1", 1, "on", "yes"]
end

defmodule Laravex.Auth.Gate do
  @moduledoc "Gate + policy registry (Laravel Gate / Policy conventions)."

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
      [{_, fun}] when is_function(fun, 2) ->
        truthy?(fun.(user, resource))

      [{_, fun}] when is_function(fun, 1) ->
        truthy?(fun.(user))

      [] ->
        Laravex.Auth.Policy.allows?(user, ability, resource)
    end
  end

  def denies?(user, ability, resource \\ nil), do: not allows?(user, ability, resource)

  def authorize(user, ability, resource \\ nil) do
    if allows?(user, ability, resource) do
      :ok
    else
      raise Laravex.Http.HttpException, status: 403, message: "This action is unauthorized."
    end
  end

  defp truthy?(true), do: true
  defp truthy?(false), do: false
  defp truthy?(nil), do: false
  defp truthy?(_), do: true
end

defmodule Laravex.Auth.Token do
  @moduledoc """
  API token store (Sanctum-like) — SQLite `personal_access_tokens` with ETS cache.

  Abilities: `create(user, "api", ["posts:read", "posts:write"])` or `["*"]`.
  Check via `token_can?/1` / `token_can?/2` after bearer boot.
  """

  @table :laravex_api_tokens
  @abilities_key :laravex_current_token_abilities

  def ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        :ets.new(@table, [:named_table, :public, :set])
      rescue
        ArgumentError -> :ok
      end
    end

    ensure_table()
    :ok
  end

  def create(user, name \\ "default", abilities \\ ["*"]) do
    ensure()
    plain = Laravex.Support.Helpers.str_random(40)
    hash = hash_token(plain)
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    abilities = normalize_abilities(abilities)

    :ets.insert(@table, {hash, %{user_id: user.id, name: name, abilities: abilities}})

    if table_ready?() do
      Laravex.Database.Query.insert("personal_access_tokens", %{
        "tokenable_type" => "App.Models.User",
        "tokenable_id" => user.id,
        "name" => name,
        "token" => hash,
        "abilities" => encode_abilities(abilities),
        "created_at" => now,
        "updated_at" => now
      })
    end

    %{"plainTextToken" => plain, "accessToken" => hash, "abilities" => abilities}
  end

  def find_user(plain_token) when is_binary(plain_token) do
    case find(plain_token) do
      %{user: user, abilities: abilities} ->
        Process.put(@abilities_key, abilities)
        user

      nil ->
        Process.delete(@abilities_key)
        nil
    end
  end

  def find(plain_token) when is_binary(plain_token) do
    ensure()
    hash = hash_token(plain_token)
    model = Laravex.Config.Repository.get("auth.providers.users.model", App.Models.User)

    case :ets.lookup(@table, hash) do
      [{_, %{user_id: id, abilities: abilities}}] ->
        case model.find(id) do
          nil -> nil
          user -> %{user: user, abilities: abilities || ["*"], token: hash}
        end

      [{_, %{user_id: id}}] ->
        case model.find(id) do
          nil -> nil
          user -> %{user: user, abilities: ["*"], token: hash}
        end

      [] ->
        if table_ready?() do
          case Laravex.Database.Query.table("personal_access_tokens")
               |> Laravex.Database.Query.where("token", hash)
               |> Laravex.Database.Query.first() do
            %{"tokenable_id" => id} = row ->
              abilities = decode_abilities(row["abilities"])
              :ets.insert(@table, {hash, %{user_id: id, name: row["name"] || "db", abilities: abilities}})

              case model.find(id) do
                nil -> nil
                user -> %{user: user, abilities: abilities, token: hash}
              end

            _ ->
              nil
          end
        else
          nil
        end
    end
  end

  @doc "Whether the current bearer token (or given abilities) allows `ability`."
  def token_can?(ability) when is_binary(ability) or is_atom(ability) do
    can?(Process.get(@abilities_key), ability)
  end

  def token_can?(abilities, ability) when is_list(abilities) do
    can?(abilities, ability)
  end

  def current_abilities, do: Process.get(@abilities_key)

  def can?(abilities, ability) do
    ability = to_string(ability)

    case normalize_abilities(abilities) do
      ["*"] -> true
      list when is_list(list) -> ability in list or "*" in list
      _ -> false
    end
  end

  defp normalize_abilities(nil), do: ["*"]
  defp normalize_abilities("*"), do: ["*"]
  defp normalize_abilities(["*"]), do: ["*"]
  defp normalize_abilities(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp normalize_abilities(other) when is_binary(other), do: decode_abilities(other)
  defp normalize_abilities(_), do: []

  defp encode_abilities(["*"]), do: "*"
  defp encode_abilities(list) when is_list(list), do: Laravex.Support.JSON.encode!(list)

  defp decode_abilities(nil), do: ["*"]
  defp decode_abilities("*"), do: ["*"]
  defp decode_abilities(json) when is_binary(json) do
    case Laravex.Support.JSON.decode(json) do
      {:ok, list} when is_list(list) -> Enum.map(list, &to_string/1)
      _ -> if json == "*", do: ["*"], else: [json]
    end
  end

  defp hash_token(plain), do: :crypto.hash(:sha256, plain) |> Base.encode16(case: :lower)

  defp ensure_table do
    unless table_ready?() do
      Laravex.Database.Connection.execute("""
      CREATE TABLE IF NOT EXISTS personal_access_tokens (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tokenable_type TEXT NOT NULL,
        tokenable_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        token TEXT NOT NULL UNIQUE,
        abilities TEXT,
        last_used_at TEXT,
        expires_at TEXT,
        created_at TEXT,
        updated_at TEXT
      )
      """)
    end
  rescue
    _ -> :ok
  end

  defp table_ready? do
    Laravex.Database.Schema.has_table?("personal_access_tokens")
  rescue
    _ -> false
  end
end
