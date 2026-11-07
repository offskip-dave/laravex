defmodule Laravex.Routing.RouteCache do
  @moduledoc """
  Persist registered HTTP routes to `bootstrap/cache/routes.term` (Laravel route:cache).
  """

  @table :laravex_routes
  @meta :laravex_route_meta

  def path(base_path \\ nil) do
    base = base_path || Laravex.Foundation.Application.base_path()
    Path.join(base, "bootstrap/cache/routes.term")
  end

  def exists?(base_path \\ nil), do: File.exists?(path(base_path))

  def cache!(base_path \\ nil) do
    Laravex.Routing.Router.ensure_tables()
    file = path(base_path)
    File.mkdir_p!(Path.dirname(file))

    named =
      case :ets.lookup(@meta, :named) do
        [{:named, map}] -> map
        _ -> %{}
      end

    payload = %{
      routes: :ets.tab2list(@table),
      named: named
    }

    File.write!(file, :erlang.term_to_binary(payload))
    :ok
  end

  def load!(base_path \\ nil) do
    file = path(base_path)

    if File.exists?(file) do
      payload = :erlang.binary_to_term(File.read!(file))
      Laravex.Routing.Router.reset()

      Enum.each(payload.routes || [], fn row ->
        :ets.insert(@table, row)
      end)

      :ets.insert(@meta, {:named, payload.named || %{}})
      true
    else
      false
    end
  rescue
    _ -> false
  end

  def clear!(base_path \\ nil) do
    file = path(base_path)
    if File.exists?(file), do: File.rm!(file)
    :ok
  end
end
