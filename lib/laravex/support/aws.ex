defmodule Laravex.Support.Aws do
  @moduledoc "Shared AWS SigV4 helpers for S3 / SQS / SES."

  def credentials do
    %{
      key: System.get_env("AWS_ACCESS_KEY_ID") || "",
      secret: System.get_env("AWS_SECRET_ACCESS_KEY") || "",
      region: System.get_env("AWS_DEFAULT_REGION") || "us-east-1"
    }
  end

  def sign_headers(method, url, service, headers, body, opts \\ []) do
    key = Keyword.get(opts, :key) || credentials().key
    secret = Keyword.get(opts, :secret) || credentials().secret
    region = Keyword.get(opts, :region) || credentials().region
    uri = if is_binary(url), do: URI.parse(url), else: url

    aws_sig_v4(method, uri, region, service, key, secret, headers, body || "")
  end

  def aws_sig_v4(method, %URI{host: host, path: path, query: query}, region, service, access_key, secret, headers, body) do
    now = DateTime.utc_now()
    amz_date = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    date_stamp = Calendar.strftime(now, "%Y%m%d")
    payload_hash = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
    host_char = to_charlist(host || "")

    headers =
      headers ++
        [
          {~c"host", host_char},
          {~c"x-amz-content-sha256", String.to_charlist(payload_hash)},
          {~c"x-amz-date", String.to_charlist(amz_date)}
        ]

    canonical_headers =
      headers
      |> Enum.map(fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map(fn {k, v} -> "#{k}:#{v}\n" end)
      |> Enum.join()

    signed_headers =
      headers
      |> Enum.map(fn {k, _} -> String.downcase(to_string(k)) end)
      |> Enum.sort()
      |> Enum.join(";")

    canonical_request =
      [
        method |> to_string() |> String.upcase(),
        path || "/",
        query || "",
        canonical_headers,
        signed_headers,
        payload_hash
      ]
      |> Enum.join("\n")

    credential_scope = "#{date_stamp}/#{region}/#{service}/aws4_request"

    string_to_sign =
      [
        "AWS4-HMAC-SHA256",
        amz_date,
        credential_scope,
        :crypto.hash(:sha256, canonical_request) |> Base.encode16(case: :lower)
      ]
      |> Enum.join("\n")

    signing_key = signing_key(secret, date_stamp, region, service)
    signature = :crypto.mac(:hmac, :sha256, signing_key, string_to_sign) |> Base.encode16(case: :lower)

    auth =
      "AWS4-HMAC-SHA256 Credential=#{access_key}/#{credential_scope}, " <>
        "SignedHeaders=#{signed_headers}, Signature=#{signature}"

    headers ++ [{~c"authorization", String.to_charlist(auth)}]
  end

  defp signing_key(secret, date, region, service) do
    k_date = :crypto.mac(:hmac, :sha256, "AWS4" <> secret, date)
    k_region = :crypto.mac(:hmac, :sha256, k_date, region)
    k_service = :crypto.mac(:hmac, :sha256, k_region, service)
    :crypto.mac(:hmac, :sha256, k_service, "aws4_request")
  end
end
