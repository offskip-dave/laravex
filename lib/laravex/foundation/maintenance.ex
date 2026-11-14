defmodule Laravex.Foundation.Maintenance do
  @moduledoc """
  Laravel-style maintenance mode.

  Supported drivers: `"file"` (default), `"cache"`, `"array"`.
  """

  @array_key {__MODULE__, :array}

  def path do
    Path.join(Laravex.Foundation.Application.base_path(), "storage/framework/down")
  end

  def driver do
    Laravex.Config.Repository.get("app.maintenance.driver", "file")
    |> to_string()
    |> String.downcase()
  end

  def enabled? do
    case driver() do
      "array" -> array_active?()
      "cache" -> cache_payload() != nil
      _ -> File.exists?(path())
    end
  end

  def down(opts \\ []) do
    payload = %{
      "time" => System.system_time(:second),
      "message" => Keyword.get(opts, :message, "Application is in maintenance mode."),
      "retry" => Keyword.get(opts, :retry, 60),
      "secret" => Keyword.get(opts, :secret),
      "allowed" => Keyword.get(opts, :allowed, [])
    }

    case driver() do
      "array" ->
        :persistent_term.put(@array_key, %{active: true, payload: payload})
        :ok

      "cache" ->
        # Uses the default cache store; `app.maintenance.store` mirrors Laravel config.
        _ = Laravex.Config.Repository.get("app.maintenance.store", "database")
        Laravex.Cache.Manager.put("laravex:maintenance", payload, nil)
        :ok

      _ ->
        File.mkdir_p!(Path.dirname(path()))
        File.write!(path(), Laravex.Support.JSON.encode!(payload))
        :ok
    end
  end

  def up do
    case driver() do
      "array" ->
        :persistent_term.put(@array_key, %{active: false, payload: %{}})
        :ok

      "cache" ->
        Laravex.Cache.Manager.forget("laravex:maintenance")
        :ok

      _ ->
        if File.exists?(path()), do: File.rm!(path())
        :ok
    end
  end

  def payload do
    if enabled?() do
      case driver() do
        "array" ->
          array_state().payload

        "cache" ->
          cache_payload() || default_payload()

        _ ->
          case Laravex.Support.JSON.decode(File.read!(path())) do
            {:ok, map} -> map
            _ -> default_payload()
          end
      end
    else
      nil
    end
  end

  defp default_payload, do: %{"message" => "Application is in maintenance mode.", "retry" => 60}

  defp array_state do
    case :persistent_term.get(@array_key, nil) do
      %{active: _, payload: _} = state -> state
      _ -> %{active: false, payload: %{}}
    end
  end

  defp array_active?, do: array_state().active == true

  defp cache_payload do
    case Laravex.Cache.Manager.get("laravex:maintenance", nil) do
      %{} = map -> map
      _ -> nil
    end
  rescue
    _ -> nil
  end
end

defmodule Laravex.Http.Middleware.PreventRequestsDuringMaintenance do
  @moduledoc "Return 503 when maintenance mode is active."

  def handle(request, _opts) do
    if Laravex.Foundation.Maintenance.enabled?() do
      data = Laravex.Foundation.Maintenance.payload() || %{}
      secret = Map.get(data, "secret")
      bypass = secret && Laravex.Http.Request.input(request, "secret") == secret

      if bypass do
        {:ok, request}
      else
        message = Map.get(data, "message") || "Service Unavailable"
        retry = Map.get(data, "retry") || 60

        resp =
          if Laravex.Http.Request.expects_json?(request) do
            Laravex.Http.Response.json(%{message: message}, 503)
          else
            Laravex.Http.Response.html(
              "<!DOCTYPE html><html><body><h1>503</h1><p>#{message}</p></body></html>",
              503
            )
          end

        {:halt, %{resp | headers: [{"retry-after", to_string(retry)} | resp.headers]}}
      end
    else
      {:ok, request}
    end
  end
end
