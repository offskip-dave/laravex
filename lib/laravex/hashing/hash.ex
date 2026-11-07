defmodule Laravex.Hashing.Hash do
  @moduledoc "Password hashing (PBKDF2) with needs_rehash? support."

  def make(value) when is_binary(value) do
    salt = :crypto.strong_rand_bytes(16)
    iterations = iterations()
    hash = :crypto.pbkdf2_hmac(:sha256, value, salt, iterations, 32)

    "pbkdf2:" <> Integer.to_string(iterations) <> ":" <> Base.encode16(salt, case: :lower) <>
      ":" <> Base.encode16(hash, case: :lower)
  end

  def check(plain, hashed) when is_binary(plain) and is_binary(hashed) do
    # Foreign bcrypt hashes ($2y$ / $2a$) are not verified here — Laravex `make/1`
    # uses PBKDF2 only. Add an optional bcrypt library if you need to verify these.
    if String.starts_with?(hashed, "$2y$") or String.starts_with?(hashed, "$2a$") do
      false
    else
      check_pbkdf2(plain, hashed)
    end
  end

  defp check_pbkdf2(plain, hashed) do
    case String.split(hashed, ":") do
      ["pbkdf2", iters, salt_hex, hash_hex] ->
        salt = Base.decode16!(salt_hex, case: :lower)
        iterations = String.to_integer(iters)
        hash = :crypto.pbkdf2_hmac(:sha256, plain, salt, iterations, 32)
        secure_eq(Base.encode16(hash, case: :lower), hash_hex)

      ["pbkdf2", salt_hex, hash_hex] ->
        # Legacy 3-part format (iterations from env)
        salt = Base.decode16!(salt_hex, case: :lower)
        hash = :crypto.pbkdf2_hmac(:sha256, plain, salt, iterations(), 32)
        secure_eq(Base.encode16(hash, case: :lower), hash_hex)

      ["hashed", _rest] ->
        hashed == legacy(plain)

      _ ->
        false
    end
  rescue
    _ -> false
  end

  def needs_rehash?(hashed) when is_binary(hashed) do
    if String.starts_with?(hashed, "$2y$") or String.starts_with?(hashed, "$2a$") do
      true
    else
      needs_rehash_pbkdf2?(hashed)
    end
  end

  def needs_rehash?(_), do: true

  defp needs_rehash_pbkdf2?(hashed) do
    case String.split(hashed, ":") do
      ["pbkdf2", iters, _salt, _hash] ->
        String.to_integer(iters) != iterations()

      ["pbkdf2", _salt, _hash] ->
        true

      ["hashed" | _] ->
        true

      _ ->
        true
    end
  rescue
    _ -> true
  end

  def legacy(password) do
    salt = <<0::128>>
    hash = :crypto.hash(:sha256, salt <> password)
    "hashed:" <> Base.encode16(salt <> hash, case: :lower)
  end

  defp iterations do
    Laravex.Env.get("BCRYPT_ROUNDS", 12) |> to_int() |> then(&(max(&1, 1) * 1000))
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
  defp to_int(_), do: 12

  defp secure_eq(a, b) do
    byte_size(a) == byte_size(b) and :crypto.hash_equals(a, b)
  end
end
