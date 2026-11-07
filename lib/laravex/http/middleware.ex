defmodule Laravex.Http.Middleware do
  @moduledoc """
  Middleware registry and pipeline (web/api groups).
  """

  defstruct groups: %{
              "web" => [
                Laravex.Http.Middleware.EncryptCookies,
                Laravex.Http.Middleware.StartSession,
                Laravex.Http.Middleware.ShareErrors,
                Laravex.Http.Middleware.VerifyCsrfToken,
                Laravex.Http.Middleware.SubstituteBindings
              ],
              "api" => [
                Laravex.Http.Middleware.SubstituteBindings
              ]
            },
            aliases: %{},
            csrf_except: []

  def new, do: %__MODULE__{}

  def append_to_group(%__MODULE__{} = middleware, group, plug) do
    groups = Map.update(middleware.groups, group, [plug], fn existing -> existing ++ [plug] end)
    %{middleware | groups: groups}
  end

  def web_group(%__MODULE__{} = m), do: Map.get(m.groups, "web", [])
  def api_group(%__MODULE__{} = m), do: Map.get(m.groups, "api", [])

  def run(request, plugs) when is_list(plugs) do
    Enum.reduce_while(plugs, {:ok, request}, fn plug, {:ok, req} ->
      case apply_plug(plug, req) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:halt, resp} -> {:halt, {:halt, resp}}
        %Laravex.Http.Response{} = resp -> {:halt, {:halt, resp}}
      end
    end)
  end

  def run_web(request, %__MODULE__{} = middleware), do: run(request, web_group(middleware))

  defp apply_plug(plug, request) when is_atom(plug) do
    plug.handle(request, [])
  end

  defp apply_plug(plug, request) when is_function(plug, 1), do: plug.(request)
end

defmodule Laravex.Http.Middleware.EncryptCookies do
  def handle(request, _opts), do: {:ok, request}
end

defmodule Laravex.Http.Middleware.ShareErrors do
  def handle(request, _opts), do: {:ok, request}
end

defmodule Laravex.Http.Middleware.SubstituteBindings do
  def handle(request, _opts), do: {:ok, request}
end
