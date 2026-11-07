defmodule Laravex.View do
  @moduledoc """
  Minimal view renderer: loads resources/views/{name}.blade.ex.html or .html.
  """

  def make(name, assigns \\ %{}) when is_binary(name) do
    base = Laravex.Foundation.Application.base_path()
    candidates = [
      Path.join([base, "resources", "views", "#{name}.blade.php"]),
      Path.join([base, "resources", "views", "#{name}.html"]),
      Path.join([base, "resources", "views", "#{name}.eex"])
    ]

    path = Enum.find(candidates, &File.exists?/1)

    unless path do
      raise "View [#{name}] not found."
    end

    contents = File.read!(path)
    rendered = render_template(contents, assigns)
    Laravex.Http.Response.html(rendered)
  end

  defp render_template(contents, assigns) do
    # Strip Blade-like @php/@verbatim blocks lightly; keep HTML as-is for welcome.
    # Replace simple {{ $var }} style if assigns provided.
    Enum.reduce(assigns, contents, fn {key, value}, acc ->
      String.replace(acc, "{{ $#{key} }}", to_string(value))
      |> String.replace("{{#{key}}}", to_string(value))
    end)
  end
end
