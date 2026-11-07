defmodule Laravex.Foundation.Maintenance do
  @moduledoc "Laravel-style maintenance mode (file driver)."

  def path do
    Path.join(Laravex.Foundation.Application.base_path(), "storage/framework/down")
  end

  def enabled? do
    File.exists?(path())
  end

  def down(opts \\ []) do
    payload = %{
      "time" => System.system_time(:second),
      "message" => Keyword.get(opts, :message, "Application is in maintenance mode."),
      "retry" => Keyword.get(opts, :retry, 60),
      "secret" => Keyword.get(opts, :secret),
      "allowed" => Keyword.get(opts, :allowed, [])
    }

    File.mkdir_p!(Path.dirname(path()))
    File.write!(path(), Laravex.Support.JSON.encode!(payload))
    :ok
  end

  def up do
    if File.exists?(path()), do: File.rm!(path())
    :ok
  end

  def payload do
    if enabled?() do
      case Laravex.Support.JSON.decode(File.read!(path())) do
        {:ok, map} -> map
        _ -> %{"message" => "Application is in maintenance mode.", "retry" => 60}
      end
    else
      nil
    end
  end
end

defmodule Laravex.Http.Middleware.PreventRequestsDuringMaintenance do
  @moduledoc "Return 503 when `storage/framework/down` exists."

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
