defmodule Laravex.Filesystem.Disks.S3 do
  @moduledoc """
  S3-compatible object storage via `:httpc` (no Hex deps).

  When `key`/`secret` are set, requests are signed with AWS SigV4 (region required).
  For local emulators without credentials, a stub `Authorization` header is sent;
  set `AWS_ENDPOINT` for MinIO path-style URLs.
  """
  @behaviour Laravex.Filesystem.Disk

  @impl true
  def root(cfg, _name) do
    bucket = Map.get(cfg, "bucket") || Map.get(cfg, :bucket) || "laravex"
    "s3://#{bucket}"
  end

  @impl true
  def ensure_supported!(_name, _cfg), do: :ok

  @multipart_threshold 5 * 1024 * 1024
  @part_size 5 * 1024 * 1024

  def put(disk, path, contents, opts \\ []) do
    contents = IO.iodata_to_binary(contents)

    if byte_size(contents) >= @multipart_threshold or Keyword.get(opts, :multipart, false) do
      put_multipart(disk, path, contents)
    else
      put_single(disk, path, contents)
    end
  end

  def get(disk, path) do
    url = object_url(disk.cfg, path)

    case request(:get, url, disk.cfg, [], "") do
      {:ok, {{_, 200, _}, _, body}} -> IO.iodata_to_binary(body)
      {:ok, {{_, status, _}, _, body}} -> raise "S3 get failed (#{status}): #{body_text(body)}"
      {:error, reason} -> raise "S3 get error: #{inspect(reason)}"
    end
  end

  @doc "Stream object body in chunks (returns iodata list of binaries)."
  def stream_get(disk, path, chunk_size \\ 1_048_576) when chunk_size > 0 do
    size = content_length(disk, path) || raise "S3 stream_get: unknown object size"
    ranges = 0..max(size - 1, 0)//chunk_size

    Enum.map(ranges, fn start ->
      stop = min(start + chunk_size - 1, size - 1)
      get_range(disk, path, start, stop)
    end)
  end

  defp put_single(disk, path, contents) do
    url = object_url(disk.cfg, path)

    headers = [
      {~c"content-type", ~c"application/octet-stream"},
      {~c"content-length", Integer.to_charlist(byte_size(contents))}
    ]

    case request(:put, url, disk.cfg, headers, contents) do
      {:ok, {{_, status, _}, _, _}} when status in 200..299 -> :ok
      {:ok, {{_, status, _}, _, body}} -> raise "S3 put failed (#{status}): #{body_text(body)}"
      {:error, reason} -> raise "S3 put error: #{inspect(reason)}"
    end
  end

  defp put_multipart(disk, path, contents) do
    upload_id = initiate_multipart(disk, path)
    parts = chunk_binary(contents, @part_size)

    etags =
      parts
      |> Enum.with_index(1)
      |> Enum.map(fn {part, n} ->
        etag = upload_part(disk, path, upload_id, n, part)
        {n, etag}
      end)

    complete_multipart(disk, path, upload_id, etags)
  end

  defp initiate_multipart(disk, path) do
    url = object_url(disk.cfg, path) <> "?uploads"
    case request(:post, url, disk.cfg, [], "") do
      {:ok, {{_, status, _}, _, body}} when status in 200..299 ->
        xml = body_text(body)

        case Regex.run(~r/<UploadId>([^<]+)<\/UploadId>/, xml) do
          [_, id] -> id
          _ -> raise "S3 multipart initiate: missing UploadId"
        end

      {:ok, {{_, status, _}, _, body}} ->
        raise "S3 multipart initiate failed (#{status}): #{body_text(body)}"

      {:error, reason} ->
        raise "S3 multipart initiate error: #{inspect(reason)}"
    end
  end

  defp upload_part(disk, path, upload_id, part_number, body) do
    url = object_url(disk.cfg, path) <> "?partNumber=#{part_number}&uploadId=#{URI.encode_www_form(upload_id)}"
    headers = [{~c"content-length", Integer.to_charlist(byte_size(body))}]

    case request(:put, url, disk.cfg, headers, body) do
      {:ok, {{_, status, _}, resp_headers, _}} when status in 200..299 ->
        etag_from_headers(resp_headers) || "\"part-#{part_number}\""

      {:ok, {{_, status, _}, _, body}} ->
        raise "S3 upload part failed (#{status}): #{body_text(body)}"

      {:error, reason} ->
        raise "S3 upload part error: #{inspect(reason)}"
    end
  end

  defp complete_multipart(disk, path, upload_id, etags) do
    url = object_url(disk.cfg, path) <> "?uploadId=#{URI.encode_www_form(upload_id)}"

    parts_xml =
      Enum.map_join(etags, "", fn {n, etag} ->
        "<Part><PartNumber>#{n}</PartNumber><ETag>#{etag}</ETag></Part>"
      end)

    body = "<CompleteMultipartUpload>#{parts_xml}</CompleteMultipartUpload>"
    headers = [{~c"content-type", ~c"application/xml"}]

    case request(:post, url, disk.cfg, headers, body) do
      {:ok, {{_, status, _}, _, _}} when status in 200..299 -> :ok
      {:ok, {{_, status, _}, _, resp}} -> raise "S3 complete multipart failed (#{status}): #{body_text(resp)}"
      {:error, reason} -> raise "S3 complete multipart error: #{inspect(reason)}"
    end
  end

  defp content_length(disk, path) do
    url = object_url(disk.cfg, path)

    case request(:head, url, disk.cfg, [], "") do
      {:ok, {{_, 200, _}, headers, _}} ->
        headers
        |> Enum.find_value(fn
          {k, v} -> if String.downcase(to_string(k)) == "content-length", do: String.to_integer(to_string(v))
          _ -> nil
        end)

      _ ->
        nil
    end
  end

  defp get_range(disk, path, start, stop) do
    url = object_url(disk.cfg, path)
    headers = [{~c"range", String.to_charlist("bytes=#{start}-#{stop}")}]

    case request(:get, url, disk.cfg, headers, "") do
      {:ok, {{_, status, _}, _, body}} when status in [200, 206] -> IO.iodata_to_binary(body)
      {:ok, {{_, status, _}, _, body}} -> raise "S3 range get failed (#{status}): #{body_text(body)}"
      {:error, reason} -> raise "S3 range get error: #{inspect(reason)}"
    end
  end

  defp chunk_binary(bin, size) when byte_size(bin) <= size, do: [bin]

  defp chunk_binary(bin, size) do
    <<chunk::binary-size(^size), rest::binary>> = bin
    [chunk | chunk_binary(rest, size)]
  end

  defp etag_from_headers(headers) do
    Enum.find_value(headers, fn
      {k, v} -> if String.downcase(to_string(k)) == "etag", do: to_string(v)
      _ -> nil
    end)
  end

  def exists?(disk, path) do
    url = object_url(disk.cfg, path)

    case request(:head, url, disk.cfg, [], "") do
      {:ok, {{_, 200, _}, _, _}} -> true
      {:ok, {{_, 404, _}, _, _}} -> false
      _ -> false
    end
  rescue
    _ -> false
  end

  def delete(disk, path) do
    url = object_url(disk.cfg, path)

    case request(:delete, url, disk.cfg, [], "") do
      {:ok, {{_, status, _}, _, _}} when status in 200..299 -> :ok
      {:ok, {{_, 404, _}, _, _}} -> :ok
      {:ok, {{_, status, _}, _, body}} -> raise "S3 delete failed (#{status}): #{body_text(body)}"
      {:error, reason} -> raise "S3 delete error: #{inspect(reason)}"
    end
  end

  def url(path, cfg) do
    public = Map.get(cfg, "url") || Map.get(cfg, :url)

    if is_binary(public) and public != "" do
      String.trim_trailing(public, "/") <> "/" <> String.trim_leading(path, "/")
    else
      object_url(cfg, path)
    end
  end

  defp object_url(cfg, path) do
    bucket = Map.get(cfg, "bucket") || Map.get(cfg, :bucket) || "laravex"
    key = String.trim_leading(path, "/")
    endpoint = Map.get(cfg, "endpoint") || Map.get(cfg, :endpoint)
    region = Map.get(cfg, "region") || Map.get(cfg, :region) || "us-east-1"

    cond do
      is_binary(endpoint) and endpoint != "" ->
        base = String.trim_trailing(endpoint, "/")

        if path_style?(cfg) do
          "#{base}/#{bucket}/#{key}"
        else
          "#{base}/#{key}"
        end

      true ->
        "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"
    end
  end

  defp path_style?(cfg) do
    Map.get(cfg, "use_path_style_endpoint") == true or
      Map.get(cfg, :use_path_style_endpoint) == true
  end

  defp request(method, url, cfg, headers, body) do
    uri = URI.parse(url)
    signed_headers = sign_headers(method, uri, cfg, headers, body)
    :httpc.request(method, {url, signed_headers}, [{:timeout, 30_000}], if(body == "", do: [], else: [body: body]))
  end

  defp sign_headers(method, %URI{} = uri, cfg, headers, body) do
    key = Map.get(cfg, "key") || Map.get(cfg, :key)
    secret = Map.get(cfg, "secret") || Map.get(cfg, :secret)
    region = to_string(Map.get(cfg, "region") || Map.get(cfg, :region) || "us-east-1")

    if is_binary(key) and key != "" and is_binary(secret) and secret != "" do
      aws_sig_v4(method, uri, region, key, secret, headers, body)
    else
      headers ++ [{~c"authorization", ~c"Laravex-S3-Stub"}]
    end
  end

  defp aws_sig_v4(method, %URI{host: host, path: path, query: query}, region, access_key, secret, headers, body) do
    service = "s3"
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
        method |> Atom.to_string() |> String.upcase(),
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

  defp body_text(body) when is_list(body), do: IO.iodata_to_binary(body)
  defp body_text(body) when is_binary(body), do: body
  defp body_text(_), do: ""
end
