defmodule Laravex.Http.Middleware.Authenticate do
  @moduledoc "Require an authenticated user (session or bearer token)."

  def handle(request, opts) do
    request = boot_user(request)

    if Laravex.Auth.Guard.check?(request) do
      {:ok, request}
    else
      if Keyword.get(opts, :json, false) or Laravex.Http.Request.expects_json?(request) do
        {:halt, Laravex.Http.Response.json(%{message: "Unauthenticated."}, 401)}
      else
        redirect = Keyword.get(opts, :redirect, "/login")
        {:halt, Laravex.Http.Response.redirect(redirect)}
      end
    end
  end

  def boot_user(request) do
    user =
      Laravex.Auth.Guard.user(request) ||
        case Laravex.Http.Request.bearer_token(request) do
          nil -> nil
          token -> Laravex.Auth.Token.find_user(token)
        end

    %{request | user: user}
  end
end

defmodule Laravex.Http.Middleware.RedirectIfAuthenticated do
  @moduledoc "Guest-only middleware (`guest` alias)."

  def handle(request, opts) do
    request = Laravex.Http.Middleware.Authenticate.boot_user(request)

    if Laravex.Auth.Guard.check?(request) do
      {:halt, Laravex.Http.Response.redirect(Keyword.get(opts, :redirect, "/"))}
    else
      {:ok, request}
    end
  end
end

defmodule Laravex.Http.Middleware.Authorize do
  @moduledoc "Authorize an ability, optionally against a route-bound model."

  def handle(request, opts) do
    request = Laravex.Http.Middleware.Authenticate.boot_user(request)
    ability = Keyword.fetch!(opts, :ability)
    resource_key = Keyword.get(opts, :resource)

    resource =
      cond do
        is_nil(resource_key) ->
          nil

        is_map(resource_key) ->
          resource_key

        true ->
          Map.get(request.route_params || %{}, to_string(resource_key)) ||
            Map.get(request.params || %{}, to_string(resource_key))
      end

    user = Laravex.Auth.Guard.user(request)

    cond do
      is_nil(user) ->
        {:halt, Laravex.Http.Response.json(%{message: "Unauthenticated."}, 401)}

      Laravex.Auth.Gate.allows?(user, ability, resource) ->
        {:ok, request}

      true ->
        {:halt, Laravex.Http.Response.json(%{message: "This action is unauthorized."}, 403)}
    end
  end
end

defmodule Laravex.Http.Middleware.ThrottleRequests do
  @moduledoc "Simple cache-backed rate limiter (`throttle:60,1` → 60/min)."

  def handle(request, opts) do
    max = Keyword.get(opts, :max, 60)
    decay = Keyword.get(opts, :decay, 1)
    ip = Laravex.Http.Request.header(request, "x-forwarded-for") || "127.0.0.1"
    key = "throttle:#{ip}:#{request.method}:#{request.path}"

    count = (Laravex.Cache.Manager.get(key) || 0) + 1
    Laravex.Cache.Manager.put(key, count, decay * 60)

    if count > max do
      {:halt,
       Laravex.Http.Response.json(%{message: "Too Many Attempts."}, 429)
       |> Map.update!(:headers, fn h -> [{"retry-after", to_string(decay * 60)} | h] end)}
    else
      {:ok, request}
    end
  end
end

defmodule Laravex.Http.Middleware.ValidateSignature do
  @moduledoc "Require a valid signed URL (`signed` alias)."

  def handle(request, _opts) do
    if Laravex.Http.UrlSigner.valid?(request) do
      {:ok, request}
    else
      {:halt, Laravex.Http.Response.html("Invalid signature.", 403)}
    end
  end
end
