defmodule Laravex.Foundation.Exceptions do
  @moduledoc """
  Exception rendering with debug HTML pages and JSON API errors.
  """

  defstruct should_render_json_when: nil, reporters: []

  def new, do: %__MODULE__{}

  def should_render_json_when(%__MODULE__{} = exceptions, fun) when is_function(fun, 1) do
    %{exceptions | should_render_json_when: fun}
  end

  def report(exceptions \\ nil, error) do
    _ = exceptions
    Laravex.Log.Logger.error(Exception.message(error), %{exception: error.__struct__})
    :ok
  end

  def render(exceptions, request, error) do
    report(exceptions, error)

    status =
      case error do
        %Laravex.Http.HttpException{status: s} -> s
        %Laravex.Support.DumpException{} -> 500
        _ -> 500
      end

    message = Exception.message(error)
    debug? = Laravex.Config.Repository.get("app.debug", false) in [true, "true", 1, "1"]

    if should_json?(exceptions, request) do
      body =
        Laravex.Support.JSON.encode!(%{
          message: message,
          exception: error.__struct__ |> to_string(),
          debug: if(debug?, do: Exception.format(:error, error, []), else: nil)
        })

      Laravex.Http.Response.new(status, body, [
        {"content-type", "application/json; charset=utf-8"}
      ])
    else
      body =
        if debug? do
          debug_page(status, message, error)
        else
          "<!DOCTYPE html><html><body><h1>#{status}</h1><p>Server Error</p></body></html>"
        end

      Laravex.Http.Response.html(body, status)
    end
  end

  defp should_json?(%{should_render_json_when: fun}, request) when is_function(fun, 1) do
    fun.(request)
  end

  defp should_json?(_, _), do: false

  defp debug_page(status, message, error) do
    """
    <!DOCTYPE html>
    <html><head><title>Laravex Exception</title>
    <style>
      body{font-family:ui-monospace,monospace;background:#0f172a;color:#e2e8f0;padding:2rem}
      h1{color:#f87171} pre{background:#1e293b;padding:1rem;overflow:auto;border-radius:8px}
    </style></head>
    <body>
      <h1>#{status} — #{html_escape(message)}</h1>
      <pre>#{html_escape(Exception.format(:error, error, []))}</pre>
    </body></html>
    """
  end

  defp html_escape(str) do
    str
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
