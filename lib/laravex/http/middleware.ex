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

  defp apply_plug(plug, request) when is_atom(plug), do: plug.handle(request, [])
  defp apply_plug(plug, request) when is_function(plug, 1), do: plug.(request)
end

defmodule Laravex.Http.Middleware.EncryptCookies do
  @moduledoc "Marks cookies as encrypted (values sealed with Crypt when APP_KEY is set)."

  def handle(request, _opts) do
    sealed =
      Map.new(request.cookies, fn {k, v} ->
        if String.starts_with?(to_string(v), "eyJpdiI") or String.contains?(to_string(v), ":") do
          {k, try_decrypt(v)}
        else
          {k, v}
        end
      end)

    {:ok, %{request | cookies: sealed}}
  end

  defp try_decrypt(v) do
    Laravex.Encryption.Crypt.decrypt(v)
  rescue
    _ -> v
  end
end

defmodule Laravex.Http.Middleware.ShareErrors do
  @moduledoc "Shares validation/flash errors from the session onto the request."

  def handle(request, _opts) do
    errors = Map.get(request.session, "_errors", %{})
    old = Map.get(request.session, "_old", %{})

    session =
      request.session
      |> Map.delete("_errors")
      |> Map.delete("_old")

    {:ok, %{request | errors: errors, old: old, session: session}}
  end
end

defmodule Laravex.Http.Middleware.SubstituteBindings do
  @moduledoc """
  Resolves route parameters that look like model bindings.
  Convention: `{user}` → App.Models.User.find(id) when that module exists.
  """

  def handle(request, _opts) do
    bindings =
      Enum.reduce(request.route_params || %{}, %{}, fn {key, value}, acc ->
        case resolve_binding(key, value) do
          nil -> acc
          model -> Map.put(acc, key, model)
        end
      end)

    params =
      Enum.reduce(bindings, request.params, fn {key, model}, acc ->
        Map.put(acc, key, model)
      end)

    {:ok, %{request | params: params, route_params: Map.merge(request.route_params || %{}, bindings)}}
  end

  defp resolve_binding(key, value) do
    mod_name = "App.Models." <> Macro.camelize(key)

    try do
      mod = String.to_existing_atom("Elixir." <> mod_name)

      if function_exported?(mod, :find, 1) do
        mod.find(value)
      else
        nil
      end
    rescue
      ArgumentError ->
        mod = Module.concat([mod_name])

        case Code.ensure_loaded(mod) do
          {:module, ^mod} ->
            if function_exported?(mod, :find, 1), do: mod.find(value), else: nil

          _ ->
            nil
        end
    end
  end
end
