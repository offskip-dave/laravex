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

  def view(name, assigns \\ %{}), do: Laravex.View.make(name, assigns)

  def route(name, params \\ %{}) do
    Laravex.Routing.Router.url(name, params)
  end

  def auth, do: Laravex.Auth.Guard

  def cache, do: Laravex.Cache.Manager

  def session, do: Laravex.Session.Store

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
