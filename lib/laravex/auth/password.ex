defmodule Laravex.Auth.Password do
  @moduledoc """
  Password broker against `password_reset_tokens` (Laravel Password facade subset).
  """

  def broker(name \\ nil) do
    name = name || Laravex.Config.Repository.get("auth.defaults.passwords", "users")
    cfg = Laravex.Config.Repository.get("auth.passwords.#{name}", %{})
    %{
      name: name,
      table: Map.get(cfg, "table") || "password_reset_tokens",
      expire: Map.get(cfg, "expire") || 60,
      throttle: Map.get(cfg, "throttle") || 60,
      provider: Map.get(cfg, "provider") || "users"
    }
  end

  @doc "Send a reset link. Returns `:sent | :throttled | :user`"
  def send_reset_link(credentials, opts \\ []) when is_map(credentials) do
    email = credentials["email"] || credentials[:email]
    b = broker(Keyword.get(opts, :broker))
    model = user_model(b)

    case model.find_by_email(email) do
      nil ->
        :user

      user ->
        if throttled?(b, email) do
          :throttled
        else
          token = create_token(b, email)
          notify_reset(user, token, opts)
          :sent
        end
    end
  end

  @doc "Reset the user's password. Returns `:reset | :token | :user`"
  def reset(credentials, opts \\ []) when is_map(credentials) do
    email = credentials["email"] || credentials[:email]
    token = credentials["token"] || credentials[:token]
    password = credentials["password"] || credentials[:password]
    b = broker(Keyword.get(opts, :broker))
    model = user_model(b)

    cond do
      is_nil(email) or is_nil(token) or is_nil(password) ->
        :token

      not token_valid?(b, email, token) ->
        :token

      true ->
        case model.find_by_email(email) do
          nil ->
            :user

          user ->
            hashed = Laravex.Hashing.Hash.make(password)
            model.save(%{user | password: hashed})
            delete_token(b, email)
            :reset
        end
    end
  end

  def create_token(email) when is_binary(email), do: create_token(broker(), email)

  def create_token(b, email) when is_map(b) and is_binary(email) do
    plain = Laravex.Support.Helpers.str_random(64)
    hash = hash_token(plain)
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    delete_token(b, email)

    Laravex.Database.Connection.execute(
      "INSERT INTO #{b.table} (email, token, created_at) VALUES (?, ?, ?)",
      [email, hash, now]
    )

    plain
  end

  def token_valid?(email, plain_token) when is_binary(email),
    do: token_valid?(broker(), email, plain_token)

  def token_valid?(b, email, plain_token) when is_map(b) do
    hash = hash_token(plain_token)

    case Laravex.Database.Connection.query(
           "SELECT token, created_at FROM #{b.table} WHERE email = ? LIMIT 1",
           [email]
         ) do
      [%{"token" => stored, "created_at" => created}] ->
        secure_compare(stored, hash) and not expired?(created, b.expire)

      _ ->
        false
    end
  rescue
    _ -> false
  end

  def delete_token(email) when is_binary(email), do: delete_token(broker(), email)

  def delete_token(b, email) when is_map(b) do
    Laravex.Database.Connection.execute("DELETE FROM #{b.table} WHERE email = ?", [email])
    :ok
  rescue
    _ -> :ok
  end

  defp throttled?(b, email) do
    case Laravex.Database.Connection.query(
           "SELECT created_at FROM #{b.table} WHERE email = ? LIMIT 1",
           [email]
         ) do
      [%{"created_at" => created}] ->
        age = age_seconds(created)
        is_integer(age) and age < b.throttle

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp notify_reset(user, token, opts) do
    if Keyword.get(opts, :notify, true) do
      notification = Laravex.Auth.ResetPasswordNotification
      Laravex.Notifications.Notifier.send(user, {notification, token})
    end

    :ok
  end

  defp user_model(b) do
    provider = b.provider
    Laravex.Config.Repository.get("auth.providers.#{provider}.model", App.Models.User)
  end

  defp hash_token(plain), do: :crypto.hash(:sha256, plain) |> Base.encode16(case: :lower)

  defp expired?(created, expire_minutes) do
    case age_seconds(created) do
      nil -> true
      age -> age > expire_minutes * 60
    end
  end

  defp age_seconds(created) when is_binary(created) do
    case DateTime.from_iso8601(created) do
      {:ok, dt, _} -> DateTime.diff(DateTime.utc_now(), dt, :second)
      _ -> nil
    end
  end

  defp age_seconds(_), do: nil

  defp secure_compare(a, b) do
    a = to_string(a)
    b = to_string(b)
    byte_size(a) == byte_size(b) and :crypto.hash_equals(a, b)
  end
end

defmodule Laravex.Auth.ResetPasswordNotification do
  @moduledoc "Default password reset notification (mail channel)."

  def via(_notifiable), do: [:mail]

  def to_mail({user, token}) do
    to_mail(user, token)
  end

  def to_mail(user, token) when is_binary(token) do
    base = Laravex.Config.Repository.get("app.url", "http://localhost")
    url = String.trim_trailing(to_string(base), "/") <> "/reset-password/#{token}?email=" <> URI.encode_www_form(user.email)

    %{
      to: user.email,
      subject: "Reset Password Notification",
      view: "mail/reset_password",
      data: %{url: url, user: user, token: token}
    }
  end
end
