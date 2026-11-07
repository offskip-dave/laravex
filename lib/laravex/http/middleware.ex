defmodule Laravex.Http.Middleware do
  @moduledoc """
  Middleware registry with Laravel-style web group stubs.
  """

  defstruct groups: %{
              "web" => [
                :encrypt_cookies,
                :add_queued_cookies_to_response,
                :start_session,
                :share_errors_from_session,
                :verify_csrf_token,
                :substitute_bindings
              ]
            },
            aliases: %{}

  def new, do: %__MODULE__{}

  def append_to_group(%__MODULE__{} = middleware, group, plug) do
    groups =
      Map.update(middleware.groups, group, [plug], fn existing -> existing ++ [plug] end)

    %{middleware | groups: groups}
  end

  def web_group(%__MODULE__{} = middleware), do: Map.get(middleware.groups, "web", [])

  @doc """
  Stub pipeline: currently a pass-through that records the group ran.
  """
  def run_web(request, %__MODULE__{} = middleware) do
    _ = web_group(middleware)
    {:ok, %{request | headers: Map.put(request.headers, "x-laravex-middleware", "web")}}
  end
end
