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

  def database_path(join \\ ""), do: Path.join(base_path("database"), join)

  def now, do: DateTime.utc_now()

  def abort(status, message \\ "Aborted") do
    raise Laravex.Http.HttpException, status: status, message: message
  end

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
