defmodule Laravex.Http.Middleware.Authenticate do
  @moduledoc "Require an authenticated user (session or bearer token)."

  def handle(request, opts) do
    request = boot_user(request)

    if Laravex.Auth.Guard.check?(request) do
      {:ok, request}
    else
      if Keyword.get(opts, :json, false) or Laravex.Http.Request.wants_json?(request) or
           Laravex.Http.Request.ajax?(request) do
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
        if Laravex.Http.Request.wants_json?(request) or Laravex.Http.Request.ajax?(request) do
          {:halt, Laravex.Http.Response.json(%{message: "Unauthenticated."}, 401)}
        else
          {:halt, Laravex.Http.Response.redirect(Keyword.get(opts, :redirect, "/login"))}
        end

      Laravex.Auth.Gate.allows?(user, ability, resource) ->
        {:ok, request}

      true ->
        if Laravex.Http.Request.wants_json?(request) or Laravex.Http.Request.ajax?(request) do
          {:halt, Laravex.Http.Response.json(%{message: "This action is unauthorized."}, 403)}
        else
          {:halt, Laravex.Http.Response.html("Forbidden", 403)}
        end
    end
  end
end

defmodule Laravex.Http.Middleware.ThrottleRequests do
  @moduledoc "Cache-backed rate limiter (`throttle:60,1` or named `throttle:api`)."

  def handle(request, opts) do
    opts =
      case Keyword.get(opts, :limiter) do
        nil -> opts
        name -> Keyword.merge(Laravex.Http.RateLimiter.resolve(name, request), opts)
      end

    max = Keyword.get(opts, :max, 60)
    decay = Keyword.get(opts, :decay, 1)
    ip = Laravex.Http.Request.ip(request)
    limiter = Keyword.get(opts, :limiter, "default")
    key = "throttle:#{limiter}:#{ip}:#{request.method}:#{request.path}"

    if Laravex.Http.RateLimiter.too_many_attempts?(key, max) do
      retry = max(Laravex.Http.RateLimiter.available_in(key), decay * 60)

      {:halt,
       Laravex.Http.Response.json(%{message: "Too Many Attempts."}, 429)
       |> Map.update!(:headers, fn h -> [{"retry-after", to_string(retry)} | h] end)}
    else
      _ = Laravex.Http.RateLimiter.hit(key, decay * 60)
      {:ok, request}
    end
  end
end

defmodule Laravex.Http.Middleware.ValidateSignature do
  @moduledoc "Require a valid signed URL (`signed` alias)."

  def handle(request, opts) do
    if Laravex.Http.UrlSigner.valid?(request, opts) do
      {:ok, request}
    else
      if Laravex.Http.Request.wants_json?(request) or Laravex.Http.Request.ajax?(request) do
        {:halt, Laravex.Http.Response.json(%{message: "Invalid signature."}, 403)}
      else
        {:halt, Laravex.Http.Response.html("Invalid signature.", 403)}
      end
    end
  end
end

defmodule Laravex.Http.Middleware.CheckTokenAbility do
  @moduledoc """
  Require bearer token abilities (`ability:posts:read` or `abilities:read,write`).
  """

  def handle(request, opts) do
    request = Laravex.Http.Middleware.Authenticate.boot_user(request)

    needed =
      cond do
        Keyword.has_key?(opts, :abilities) ->
          opts
          |> Keyword.get(:abilities)
          |> List.wrap()
          |> Enum.map(&to_string/1)

        Keyword.has_key?(opts, :ability) ->
          [to_string(Keyword.get(opts, :ability))]

        true ->
          []
      end

    cond do
      is_nil(Laravex.Auth.Guard.user(request)) ->
        {:halt, Laravex.Http.Response.json(%{message: "Unauthenticated."}, 401)}

      needed == [] ->
        {:ok, request}

      Enum.all?(needed, &Laravex.Auth.Token.token_can?/1) ->
        {:ok, request}

      true ->
        {:halt, Laravex.Http.Response.json(%{message: "Invalid ability provided for token."}, 403)}
    end
  end
end

defmodule Laravex.Http.Middleware.EnsureEmailIsVerified do
  @moduledoc "Require `email_verified_at` on the authenticated user (`verified` alias)."

  def handle(request, opts) do
    request = Laravex.Http.Middleware.Authenticate.boot_user(request)
    user = Laravex.Auth.Guard.user(request)

    cond do
      is_nil(user) ->
        unauthenticated(request, opts)

      verified?(user) ->
        {:ok, request}

      true ->
        if Laravex.Http.Request.wants_json?(request) or Laravex.Http.Request.ajax?(request) do
          {:halt, Laravex.Http.Response.json(%{message: "Your email address is not verified."}, 409)}
        else
          redirect = Keyword.get(opts, :redirect, "/email/verify")
          {:halt, Laravex.Http.Response.redirect(redirect)}
        end
    end
  end

  defp verified?(user) do
    value =
      cond do
        function_exported?(user.__struct__, :get_attribute, 2) ->
          user.__struct__.get_attribute(user, "email_verified_at")

        true ->
          Map.get(user, :email_verified_at) || Map.get(user, "email_verified_at")
      end

    not is_nil(value) and value != ""
  end

  defp unauthenticated(request, opts) do
    if Laravex.Http.Request.wants_json?(request) or Laravex.Http.Request.ajax?(request) do
      {:halt, Laravex.Http.Response.json(%{message: "Unauthenticated."}, 401)}
    else
      {:halt, Laravex.Http.Response.redirect(Keyword.get(opts, :redirect_login, "/login"))}
    end
  end
end

defmodule Laravex.Http.Middleware.RequirePasswordConfirmation do
  @moduledoc """
  Require a recent password confirmation (`password.confirm` alias).

  Session key: `auth.password_confirmed_at` (unix seconds). Timeout from
  `auth.password_timeout` (default 10800 = 3 hours).
  """

  def handle(request, opts) do
    request = Laravex.Http.Middleware.Authenticate.boot_user(request)

    cond do
      is_nil(Laravex.Auth.Guard.user(request)) ->
        if Laravex.Http.Request.wants_json?(request) or Laravex.Http.Request.ajax?(request) do
          {:halt, Laravex.Http.Response.json(%{message: "Unauthenticated."}, 401)}
        else
          {:halt, Laravex.Http.Response.redirect(Keyword.get(opts, :redirect_login, "/login"))}
        end

      confirmed_recently?(request, opts) ->
        {:ok, request}

      true ->
        if Laravex.Http.Request.wants_json?(request) or Laravex.Http.Request.ajax?(request) do
          {:halt, Laravex.Http.Response.json(%{message: "Password confirmation required."}, 423)}
        else
          redirect = Keyword.get(opts, :redirect, "/confirm-password")

          request =
            Laravex.Session.Store.put(request, "url.intended", Laravex.Http.Request.full_url(request))

          Process.put(:laravex_request, request)

          if is_binary(request.session_id) do
            Laravex.Session.Store.save(request.session_id, request.session)
          end

          {:halt, Laravex.Http.Response.redirect(redirect)}
        end
    end
  end

  @doc "Mark the password as confirmed now (call after successful re-entry)."
  def confirm(request) do
    now = System.system_time(:second)
    Laravex.Session.Store.put(request, "auth.password_confirmed_at", now)
  end

  defp confirmed_recently?(request, opts) do
    timeout =
      Keyword.get(opts, :timeout) ||
        Laravex.Config.Repository.get("auth.password_timeout", 10_800)

    timeout = to_integer(timeout, 10_800)
    confirmed_at = Laravex.Session.Store.get(request, "auth.password_confirmed_at")

    case to_integer(confirmed_at, nil) do
      nil -> false
      at -> System.system_time(:second) - at < timeout
    end
  end

  defp to_integer(v, _default) when is_integer(v), do: v

  defp to_integer(v, default) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, _} -> n
      :error -> default
    end
  end

  defp to_integer(_, default), do: default
end

defmodule Laravex.Http.Middleware.EnsureFrontendRequestsAreStateful do
  @moduledoc """
  SPA Sanctum: treat matching Origin/Referer hosts as stateful (session + CSRF on API).

  Domains from `sanctum.stateful` or `session.domain`. Route alias: `sanctum.stateful`.
  """

  @stateful_plugs [
    Laravex.Http.Middleware.EncryptCookies,
    Laravex.Http.Middleware.AddQueuedCookies,
    Laravex.Http.Middleware.StartSession,
    Laravex.Http.Middleware.AuthenticateSession,
    Laravex.Http.Middleware.VerifyCsrfToken
  ]

  def handle(request, _opts) do
    if from_stateful_domain?(request) do
      case Laravex.Http.Middleware.run(request, @stateful_plugs) do
        {:ok, next} -> {:ok, next}
        {:halt, resp} -> {:halt, resp}
      end
    else
      {:ok, request}
    end
  end

  defp from_stateful_domain?(request) do
    host = request_origin_host(request)
    host != nil and host in stateful_domains()
  end

  defp request_origin_host(request) do
    cond do
      origin = Laravex.Http.Request.header(request, "origin") ->
        uri_host(origin)

      referer = Laravex.Http.Request.header(request, "referer") ->
        uri_host(referer)

      true ->
        nil
    end
  end

  defp uri_host(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: h} when is_binary(h) and h != "" -> String.downcase(h)
      _ -> nil
    end
  end

  defp uri_host(_), do: nil

  defp stateful_domains do
    raw =
      Laravex.Config.Repository.get("sanctum.stateful") ||
        case Laravex.Config.Repository.get("session.domain") do
          nil -> ["localhost", "127.0.0.1", "::1"]
          domain -> [domain]
        end

    raw
    |> List.wrap()
    |> Enum.flat_map(&String.split(to_string(&1), ",", trim: true))
    |> Enum.map(&normalize_stateful_domain/1)
    |> Enum.uniq()
  end

  defp normalize_stateful_domain(domain) do
    domain
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> then(fn d ->
      case URI.parse("http://#{d}") do
        %URI{host: h} when is_binary(h) and h != "" -> h
        _ -> d
      end
    end)
  end
end
