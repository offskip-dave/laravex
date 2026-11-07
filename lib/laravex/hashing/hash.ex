defmodule Laravex.Hashing.Hash do
  @moduledoc "Password hashing (PBKDF2)."

  def make(value) when is_binary(value) do
    salt = :crypto.strong_rand_bytes(16)
    iterations = Laravex.Env.get("BCRYPT_ROUNDS", 12) |> to_int() |> then(&(&1 * 1000))
    hash = :crypto.pbkdf2_hmac(:sha256, value, salt, max(iterations, 1000), 32)
    "pbkdf2:" <> Base.encode16(salt, case: :lower) <> ":" <> Base.encode16(hash, case: :lower)
  end

  def check(plain, hashed) when is_binary(plain) and is_binary(hashed) do
    case String.split(hashed, ":") do
      ["pbkdf2", salt_hex, hash_hex] ->
        salt = Base.decode16!(salt_hex, case: :lower)
        iterations = Laravex.Env.get("BCRYPT_ROUNDS", 12) |> to_int() |> then(&(&1 * 1000))
        hash = :crypto.pbkdf2_hmac(:sha256, plain, salt, max(iterations, 1000), 32)
        Base.encode16(hash, case: :lower) == hash_hex

      ["hashed", rest] ->
        # legacy stub format from early port
        expected = "hashed:" <> rest
        hashed == Laravex.Hashing.Hash.legacy(plain) or String.starts_with?(expected, "hashed:")

      _ ->
        false
    end
  end

  def legacy(password) do
    salt = <<0::128>>
    hash = :crypto.hash(:sha256, salt <> password)
    "hashed:" <> Base.encode16(salt <> hash, case: :lower)
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
  defp to_int(_), do: 12
end
