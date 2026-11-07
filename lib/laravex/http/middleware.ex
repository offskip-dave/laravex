defmodule Laravex.Http.Middleware do
  @moduledoc """
  Middleware registry and pipeline (web/api groups).
  """

  defstruct groups: %{
              "web" => [
                Laravex.Http.Middleware.EncryptCookies,
                Laravex.Http.Middleware.StartSession,
                Laravex.Http.Middleware.MethodOverride,
                Laravex.Http.Middleware.ShareErrors,
                Laravex.Http.Middleware.ShareFlash,
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

  def resolve_alias(name) when is_atom(name), do: {name, []}

  def resolve_alias(name) when is_binary(name) do
    {alias_name, arg} =
      case String.split(name, ":", parts: 2) do
        [a, rest] -> {a, rest}
        [a] -> {a, nil}
      end

    case alias_name do
      "auth" ->
        {Laravex.Http.Middleware.Authenticate, json: arg == "api"}

      "guest" ->
        {Laravex.Http.Middleware.RedirectIfAuthenticated, []}

      "signed" ->
        {Laravex.Http.Middleware.ValidateSignature, []}

      "can" ->
        {ability, resource} =
          case String.split(arg || "", ",", parts: 2) do
            [ab, res] -> {String.trim(ab), String.trim(res)}
            [ab] -> {String.trim(ab), nil}
          end

        {Laravex.Http.Middleware.Authorize, ability: ability, resource: resource}

      "throttle" ->
        opts =
          cond do
            is_nil(arg) or arg == "" ->
              [max: 60, decay: 1]

            String.contains?(arg, ",") ->
              case String.split(arg, ",", parts: 2) do
                [m, d] ->
                  [max: String.to_integer(String.trim(m)), decay: String.to_integer(String.trim(d))]

                [m] ->
                  [max: String.to_integer(String.trim(m)), decay: 1]
              end

            Regex.match?(~r/^\d+$/, arg) ->
              [max: String.to_integer(arg), decay: 1]

            true ->
              [limiter: arg]
          end

        {Laravex.Http.Middleware.ThrottleRequests, opts}

      other ->
        {Module.concat([other]), []}
    end
  end

  defp apply_plug({plug, opts}, request) when is_atom(plug), do: plug.handle(request, List.wrap(opts) |> normalize_opts())
  defp apply_plug(plug, request) when is_atom(plug), do: plug.handle(request, [])
  defp apply_plug(plug, request) when is_function(plug, 1), do: plug.(request)

  defp normalize_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: opts, else: []
  end
end

defmodule Laravex.Http.Middleware.EncryptCookies do
  @moduledoc """
  Decrypt inbound cookies when `session.encrypt` is true (or value looks sealed).
  Encrypt outbound Set-Cookie values in `terminate/2`.
  """

  def handle(request, _opts) do
    encrypt? = truthy?(Laravex.Config.Repository.get("session.encrypt", false))

    sealed =
      Map.new(request.cookies, fn {k, v} ->
        if encrypt? or looks_encrypted?(v) do
          {k, try_decrypt(v)}
        else
          {k, v}
        end
      end)

    {:ok, %{request | cookies: sealed}}
  end

  def terminate(_request, %Laravex.Http.Response{} = response) do
    if truthy?(Laravex.Config.Repository.get("session.encrypt", false)) do
      cookies =
        Enum.map(response.cookies, fn cookie ->
          case String.split(cookie, "=", parts: 2) do
            [name, rest] ->
              {value, attrs} =
                case String.split(rest, ";", parts: 2) do
                  [v, a] -> {URI.decode(String.trim(v)), a}
                  [v] -> {URI.decode(String.trim(v)), nil}
                end

              if looks_encrypted?(value) do
                cookie
              else
                sealed = Laravex.Encryption.Crypt.encrypt(value)
                if attrs, do: "#{name}=#{URI.encode(sealed)};#{attrs}", else: "#{name}=#{URI.encode(sealed)}"
              end

            _ ->
              cookie
          end
        end)

      %{response | cookies: cookies}
    else
      response
    end
  end

  defp looks_encrypted?(v) do
    s = to_string(v)
    # AES-GCM payloads from Crypt are base64 (often start with iv+tag bytes → varied)
    byte_size(s) > 40 and match?({:ok, _}, Base.decode64(s))
  end

  defp try_decrypt(v) do
    Laravex.Encryption.Crypt.decrypt(v)
  rescue
    _ -> v
  end

  defp truthy?(v), do: v in [true, "true", 1, "1"]
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

defmodule Laravex.Http.Middleware.ShareFlash do
  @moduledoc "Ages `_flash.*` session keys onto `request.flash` for one request."

  def handle(request, _opts) do
    {flash, session} =
      Enum.reduce(request.session, {%{}, %{}}, fn {k, v}, {flash, session} ->
        key = to_string(k)

        if String.starts_with?(key, "_flash.") do
          {Map.put(flash, String.trim_leading(key, "_flash."), v), session}
        else
          {flash, Map.put(session, key, v)}
        end
      end)

    {:ok, %{request | flash: flash, session: session}}
  end
end

defmodule Laravex.Http.Middleware.MethodOverride do
  @moduledoc "Honor `_method` spoofing on POST (Laravel method field)."

  def handle(%{method: "POST"} = request, _opts) do
    case Map.get(request.params, "_method") || Map.get(request.params, :_method) do
      nil ->
        {:ok, request}

      method when is_binary(method) ->
        {:ok, %{request | method: String.upcase(method)}}

      _ ->
        {:ok, request}
    end
  end

  def handle(request, _opts), do: {:ok, request}
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
