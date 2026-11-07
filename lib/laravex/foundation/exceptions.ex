defmodule Laravex.Foundation.Exceptions do
  @moduledoc """
  Exception rendering with debug HTML pages and JSON API errors.
  """

  defstruct should_render_json_when: nil, reporters: []

  def new, do: %__MODULE__{}

  def should_render_json_when(%__MODULE__{} = exceptions, fun) when is_function(fun, 1) do
    %{exceptions | should_render_json_when: fun}
  end

  def reportable(%__MODULE__{} = exceptions, fun) when is_function(fun, 1) do
    %{exceptions | reporters: exceptions.reporters ++ [fun]}
  end

  def report(exceptions \\ nil, error) do
    reporters =
      case exceptions do
        %{reporters: list} when is_list(list) -> list
        _ -> []
      end

    Enum.each(reporters, fn
      fun when is_function(fun, 1) ->
        try do
          fun.(error)
        rescue
          _ -> :ok
        end

      _ ->
        :ok
    end)

    Laravex.Log.Logger.error(Exception.message(error), %{exception: error.__struct__})
    :ok
  end

  def render(exceptions, request, error) do
    case error do
      %Laravex.Validation.Failed{errors: errors, request: failed_request} ->
        render_validation_failed(exceptions, failed_request || request, errors)

      _ ->
        report(exceptions, error)

        status = status_for(error)
        message = public_message(error, status)
        debug? = Laravex.Config.Repository.get("app.debug", false) in [true, "true", 1, "1"]

        if should_json?(exceptions, request) do
          body =
            Laravex.Support.JSON.encode!(%{
              message: message,
              exception: if(debug?, do: error.__struct__ |> to_string(), else: nil),
              debug: if(debug?, do: Exception.format(:error, error, []), else: nil)
            })

          Laravex.Http.Response.new(status, body, [
            {"content-type", "application/json; charset=utf-8"}
          ])
        else
          body =
            if debug? do
              debug_page(status, Exception.message(error), error)
            else
              "<!DOCTYPE html><html><body><h1>#{status}</h1><p>#{html_escape(message)}</p></body></html>"
            end

          Laravex.Http.Response.html(body, status)
        end
    end
  end

  defp status_for(%Laravex.Http.HttpException{status: s}) when is_integer(s), do: s
  defp status_for(%Laravex.Database.ModelNotFoundException{}), do: 404
  defp status_for(%Laravex.Support.DumpException{}), do: 500
  defp status_for(_), do: 500

  defp public_message(%Laravex.Http.HttpException{message: m}, _status)
       when is_binary(m) and m != "",
       do: m

  defp public_message(%Laravex.Database.ModelNotFoundException{}, _status), do: "Not Found"

  defp public_message(_error, status) do
    case status do
      401 -> "Unauthenticated."
      403 -> "This action is unauthorized."
      404 -> "Not Found"
      419 -> "Page Expired"
      429 -> "Too Many Attempts."
      _ -> "Server Error"
    end
  end

  defp render_validation_failed(exceptions, request, errors) do
    if should_json?(exceptions, request) do
      resp = Laravex.Http.Response.json(%{message: "The given data was invalid.", errors: errors}, 422)
      Laravex.Http.Kernel.persist_session(request, resp)
    else
      back =
        Laravex.Http.Request.header(request, "referer") ||
          Map.get(request.session || %{}, "_previous.url") ||
          "/"

      resp = Laravex.Http.Response.redirect(back)
      Laravex.Http.Kernel.persist_session(request, resp)
    end
  end

  defp should_json?(%{should_render_json_when: fun}, request) when is_function(fun, 1) do
    fun.(request)
  end

  defp should_json?(_, request) do
    Laravex.Http.Request.wants_json?(request) or Laravex.Http.Request.ajax?(request)
  end

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
