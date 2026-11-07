defmodule Laravex.Http.UrlSigner do
  @moduledoc "HMAC-signed URLs with optional expiry (Laravel signed routes)."

  def sign(path, opts \\ []) when is_binary(path) do
    expires = Keyword.get(opts, :expires)
    expires = normalize_expires(expires)
    base = strip_signature(path)

    params =
      URI.decode_query(uri_query(base))
      |> then(fn q ->
        if expires, do: Map.put(q, "expires", to_string(expires)), else: q
      end)

    path_only = uri_path(base)
    payload = payload(path_only, params)
    signature = hmac(payload)
    query = params |> Map.put("signature", signature) |> URI.encode_query()
    path_only <> "?" <> query
  end

  def valid?(path_or_request, opts \\ []) do
    ignore =
      opts
      |> Keyword.get(:ignore, [])
      |> List.wrap()
      |> Enum.map(&to_string/1)

    {path, query} =
      case path_or_request do
        %Laravex.Http.Request{path: path, query: query} ->
          {path, stringify_map(query)}

        path when is_binary(path) ->
          {uri_path(path), URI.decode_query(uri_query(path))}
      end

    signature = Map.get(query, "signature")
    expires = Map.get(query, "expires")

    cond do
      is_nil(signature) or signature == "" ->
        false

      expires && String.to_integer(expires) < System.system_time(:second) ->
        false

      true ->
        params =
          query
          |> Map.delete("signature")
          |> Map.drop(ignore)

        expected = hmac(payload(path, params))
        secure_compare(expected, signature)
    end
  rescue
    _ -> false
  end

  def temporary(path, seconds) when is_integer(seconds) do
    sign(path, expires: System.system_time(:second) + seconds)
  end

  defp payload(path, params) do
    sorted =
      params
      |> Enum.sort_by(fn {k, _} -> k end)
      |> URI.encode_query()

    path <> "?" <> sorted
  end

  defp hmac(payload) do
    key = app_key()
    :crypto.mac(:hmac, :sha256, key, payload) |> Base.encode16(case: :lower)
  end

  defp app_key do
    app_key =
      Laravex.Config.Repository.get("app.key") || Laravex.Env.get("APP_KEY") ||
        "base64:laravex-dev-key-32bytes!!"

    app_key
    |> String.replace_prefix("base64:", "")
    |> then(fn k ->
      case Base.decode64(k) do
        {:ok, bin} when byte_size(bin) >= 16 -> bin
        _ -> :crypto.hash(:sha256, k)
      end
    end)
  end

  defp normalize_expires(nil), do: nil
  defp normalize_expires(%DateTime{} = dt), do: DateTime.to_unix(dt)
  defp normalize_expires(n) when is_integer(n), do: n

  defp strip_signature(path) do
    uri = URI.parse(path)
    query = (uri.query || "") |> URI.decode_query() |> Map.delete("signature") |> URI.encode_query()
    path_only = uri.path || path
    if query == "", do: path_only, else: path_only <> "?" <> query
  end

  defp uri_path(path) do
    case URI.parse(path) do
      %URI{path: p} when is_binary(p) and p != "" -> p
      _ -> path |> String.split("?", parts: 2) |> hd()
    end
  end

  defp uri_query(path) do
    case URI.parse(path) do
      %URI{query: q} when is_binary(q) -> q
      _ ->
        case String.split(path, "?", parts: 2) do
          [_, q] -> q
          _ -> ""
        end
    end
  end

  defp stringify_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp secure_compare(a, b) do
    a = to_string(a)
    b = to_string(b)
    byte_size(a) == byte_size(b) and :crypto.hash_equals(a, b)
  end
end
