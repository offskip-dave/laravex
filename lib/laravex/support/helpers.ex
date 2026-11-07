defmodule Laravex.Support.Helpers do
  @moduledoc """
  Laravel-style helpers imported where useful.
  """

  def config(key, default \\ nil), do: Laravex.Config.Repository.get(key, default)

  def env(key, default \\ nil), do: Laravex.Env.get(key, default)

  def base_path(join \\ ""), do: Path.join(Laravex.Foundation.Application.base_path(), join)

  def storage_path(join \\ ""), do: Path.join(base_path("storage"), join)

  def public_path(join \\ ""), do: Path.join(base_path("public"), join)

  def resource_path(join \\ ""), do: Path.join(base_path("resources"), join)

  @doc "Absolute or rooted URL for a public asset path."
  def asset(path) when is_binary(path) do
    app_url = Laravex.Config.Repository.get("app.url") || Laravex.Env.get("APP_URL", "")
    path = "/" <> String.trim_leading(path, "/")

    if is_binary(app_url) and app_url != "" do
      String.trim_trailing(app_url, "/") <> path
    else
      path
    end
  end

  def storage_url(path, disk \\ "public") when is_binary(path) do
    Laravex.Filesystem.Storage.url(path, disk)
  end

  def database_path(join \\ ""), do: Path.join(base_path("database"), join)

  def now, do: DateTime.utc_now()

  @spec abort(term()) :: no_return()
  @spec abort(term(), term()) :: no_return()
  def abort(status, message \\ "Aborted") do
    raise Laravex.Http.HttpException, status: status, message: message
  end

  def abort_if(condition, status, message \\ "Aborted") do
    if truthy?(condition), do: abort(status, message)
    :ok
  end

  def abort_unless(condition, status, message \\ "Aborted") do
    if truthy?(condition), do: :ok, else: abort(status, message)
  end

  def blank?(value) do
    cond do
      is_nil(value) -> true
      value == false -> true
      value == "" -> true
      is_list(value) and value == [] -> true
      is_map(value) and map_size(value) == 0 -> true
      is_binary(value) and String.trim(value) == "" -> true
      true -> false
    end
  end

  def filled?(value), do: not blank?(value)

  def data_get(target, key, default \\ nil) do
    Laravex.Support.Arr.get(as_map(target), key, default)
  end

  def data_set(target, key, value) do
    Laravex.Support.Arr.set(as_map(target), key, value)
  end

  def value(v) when is_function(v, 0), do: v.()
  def value(v), do: v

  def value(v, fun) when is_function(fun, 1), do: fun.(v)

  def tap(v, fun) when is_function(fun, 1) do
    fun.(v)
    v
  end

  defp as_map(%{__struct__: _} = struct), do: Map.from_struct(struct)
  defp as_map(map) when is_map(map), do: map
  defp as_map(other), do: %{"value" => other}

  defp truthy?(v) when v in [false, nil, 0, "", "0"], do: false
  defp truthy?(_), do: true

  def redirect(to) when is_binary(to) do
    Laravex.Http.Response.redirect(to)
  end

  def redirect_with(to, flash) when is_binary(to) and is_map(flash) do
    case Process.get(:laravex_request) do
      nil ->
        redirect(to)

      request ->
        request =
          Enum.reduce(flash, request, fn {k, v}, req ->
            Laravex.Session.Store.flash(req, k, v)
          end)

        Process.put(:laravex_request, request)
        redirect(to)
    end
  end

  @doc "Flash current request params as old input (Laravel `withInput`)."
  def with_input(response) do
    case Process.get(:laravex_request) do
      nil ->
        response

      request ->
        request = Laravex.Session.Store.put(request, "_old", request.params || %{})
        Process.put(:laravex_request, request)
        response
    end
  end

  def redirect_with_input(to) when is_binary(to), do: to |> redirect() |> with_input()

  @doc "Store intended URL for post-login redirect."
  def intended(url) when is_binary(url) do
    case Process.get(:laravex_request) do
      nil ->
        :ok

      request ->
        request = Laravex.Session.Store.put(request, "url.intended", url)
        Process.put(:laravex_request, request)
        :ok
    end
  end

  @doc "Redirect to previously intended URL (or fallback)."
  def redirect_intended(fallback \\ "/") do
    case Process.get(:laravex_request) do
      nil ->
        redirect(fallback)

      request ->
        to = Map.get(request.session || %{}, "url.intended") || fallback
        request = Laravex.Session.Store.put(request, "url.intended", nil)
        Process.put(:laravex_request, request)
        redirect(to)
    end
  end

  def to_route(name, params \\ %{}) do
    redirect(Laravex.Routing.Router.url(name, params))
  end

  def away(url) when is_binary(url), do: redirect(url)

  def back(fallback \\ "/") do
    case Process.get(:laravex_request) do
      nil ->
        redirect(fallback)

      request ->
        to =
          Laravex.Http.Request.header(request, "referer") ||
            Map.get(request.session || %{}, "_previous.url") ||
            fallback

        redirect(to)
    end
  end

  def old(key, default \\ "") do
    case Process.get(:laravex_request) do
      %{old: old} when is_map(old) ->
        Map.get(old, to_string(key)) || Map.get(old, key, default)

      _ ->
        default
    end
  end

  def session_get(key, default \\ nil) do
    case Process.get(:laravex_request) do
      %{flash: flash, session: session} when is_map(flash) ->
        Map.get(flash, to_string(key)) ||
          Map.get(flash, key) ||
          Map.get(session || %{}, to_string(key), default)

      %{session: session} when is_map(session) ->
        Map.get(session, to_string(key), default)

      _ ->
        default
    end
  end

  def flash(key, value) do
    case Process.get(:laravex_request) do
      nil ->
        value

      request ->
        request = Laravex.Session.Store.flash(request, key, value)
        Process.put(:laravex_request, request)
        value
    end
  end

  def flash_now(key, value) do
    case Process.get(:laravex_request) do
      nil ->
        Process.put(:laravex_flash_now, Map.put(Process.get(:laravex_flash_now, %{}), to_string(key), value))
        value

      request ->
        request = Laravex.Session.Store.flash_now(request, key, value)
        Process.put(:laravex_request, request)
        value
    end
  end

  def view(name, assigns \\ %{}), do: Laravex.View.make(name, assigns)

  def route(name, params \\ %{}) do
    Laravex.Routing.Router.url(name, params)
  end

  def signed_route(name, params \\ %{}, opts \\ []) do
    Laravex.Http.UrlSigner.sign(route(name, params), opts)
  end

  def temporary_signed_route(name, seconds, params \\ %{}) do
    Laravex.Http.UrlSigner.temporary(route(name, params), seconds)
  end

  def auth, do: Laravex.Auth.Guard

  def cache, do: Laravex.Cache.Manager

  def session, do: Laravex.Session.Store

  def storage, do: Laravex.Filesystem.Storage

  def gate, do: Laravex.Auth.Gate

  def ___(key, replace \\ %{}, locale \\ nil) do
    Laravex.Translation.get(key, replace, locale)
  end

  @spec dd(term()) :: no_return()
  def dd(value) do
    IO.puts(inspect(value, pretty: true, limit: :infinity))
    raise Laravex.Support.DumpException, value: value
  end

  def dump(value) do
    IO.puts(inspect(value, pretty: true, limit: :infinity))
    value
  end

  def collect(enumerable), do: Laravex.Support.Collection.new(enumerable)

  def validated(key \\ nil) do
    case Process.get(:laravex_request) do
      %{validated: validated} when is_map(validated) ->
        if is_nil(key), do: validated, else: Map.get(validated, to_string(key))

      _ ->
        if is_nil(key), do: %{}, else: nil
    end
  end

  def http, do: Laravex.Http.Client

  def bus, do: Laravex.Bus

  def cookie(name) when is_binary(name) or is_atom(name) do
    case Process.get(:laravex_request) do
      %{cookies: cookies} when is_map(cookies) ->
        Map.get(cookies, to_string(name))

      _ ->
        nil
    end
  end

  def cookie(name, value, opts \\ []) do
    Laravex.Http.CookieJar.queue(name, value, opts)
    value
  end

  def paginator_links(pager, path \\ "/"), do: Laravex.Http.Paginator.links(pager, path)

  def str, do: Laravex.Support.Str
  def arr, do: Laravex.Support.Arr

  def str_random(n \\ 16) do
    :crypto.strong_rand_bytes(n) |> Base.url_encode64(padding: false) |> binary_part(0, n)
  end
end

defmodule Laravex.Support.DumpException do
  defexception [:value]
  def message(%{value: v}), do: "dd(): #{inspect(v)}"
end

defmodule Laravex.Http.HttpException do
  defexception [:status, :message]
  def message(%{message: m}), do: m
end
