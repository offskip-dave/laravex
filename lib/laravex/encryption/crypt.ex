defmodule Laravex.Encryption.Crypt do
  @moduledoc "APP_KEY based encrypt/decrypt (AES-256-GCM)."

  def encrypt(value) when is_binary(value) do
    key = key()
    iv = :crypto.strong_rand_bytes(12)
    {cipher, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, value, "", 16, true)
    Base.encode64(iv <> tag <> cipher)
  end

  def decrypt(payload) when is_binary(payload) do
    key = key()
    raw = Base.decode64!(payload)
    <<iv::binary-size(12), tag::binary-size(16), cipher::binary>> = raw
    :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, cipher, "", tag, false)
  end

  defp key do
    app_key = Laravex.Config.Repository.get("app.key") || Laravex.Env.get("APP_KEY") || "base64:laravex-dev-key-32bytes!!"

    app_key
    |> String.replace_prefix("base64:", "")
    |> then(fn k ->
      decoded = Base.decode64(k)
      case decoded do
        {:ok, bin} when byte_size(bin) >= 32 -> binary_part(bin, 0, 32)
        _ -> :crypto.hash(:sha256, k)
      end
    end)
  end
end
