defmodule Laravex.Foundation.Exceptions do
  @moduledoc """
  Exception rendering hooks matching Laravel's withExceptions callback.
  """

  defstruct should_render_json_when: nil

  def new, do: %__MODULE__{}

  def should_render_json_when(%__MODULE__{} = exceptions, fun) when is_function(fun, 1) do
    %{exceptions | should_render_json_when: fun}
  end

  def render(exceptions, request, error) do
    message = Exception.message(error)
    status = 500

    if should_json?(exceptions, request) do
      body = JasonCompat.encode!(%{message: message, exception: error.__struct__ |> to_string()})

      Laravex.Http.Response.new(status, body, [
        {"content-type", "application/json; charset=utf-8"}
      ])
    else
      Laravex.Http.Response.new(status, message, [{"content-type", "text/plain; charset=utf-8"}])
    end
  end

  defp should_json?(%{should_render_json_when: fun}, request) when is_function(fun, 1) do
    fun.(request)
  end

  defp should_json?(_, _), do: false
end

defmodule JasonCompat do
  @moduledoc false

  def encode!(map) when is_map(map) do
    "{" <>
      (map
       |> Enum.map(fn {k, v} ->
         ~s("#{escape(to_string(k))}":#{encode_value(v)})
       end)
       |> Enum.join(",")) <> "}"
  end

  defp encode_value(nil), do: "null"
  defp encode_value(v) when is_binary(v), do: ~s("#{escape(v)}")
  defp encode_value(v) when is_atom(v), do: ~s("#{escape(Atom.to_string(v))}")
  defp encode_value(v) when is_integer(v) or is_float(v), do: to_string(v)
  defp encode_value(v), do: ~s("#{escape(inspect(v))}")

  defp escape(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end
end
