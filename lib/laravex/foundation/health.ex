defmodule Laravex.Foundation.Health do
  @moduledoc "JSON health check with database ping (alongside plain `/up`)."

  def check do
    db =
      try do
        case Laravex.Database.Connection.query("SELECT 1 AS ok", []) do
          [%{"ok" => _}] -> "ok"
          _ -> "degraded"
        end
      rescue
        _ -> "unavailable"
      end

    status = if db == "ok", do: 200, else: 503

    Laravex.Http.Response.json(
      %{
        status: if(db == "ok", do: "ok", else: "degraded"),
        app: Laravex.Config.Repository.get("app.name", "Laravex"),
        checks: %{
          database: db
        }
      },
      status
    )
  end
end
