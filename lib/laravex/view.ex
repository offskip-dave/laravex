defmodule Laravex.View do
  @moduledoc """
  Blade-like view renderer: {{ }}, @csrf, @vite, @if, @foreach, @error, layouts.
  """

  def make(name, assigns \\ %{}) when is_binary(name) do
    base = Laravex.Foundation.Application.base_path()
    path = find_view(base, name)
    unless path, do: raise("View [#{name}] not found.")

    contents = File.read!(path)
    rendered = render_string(contents, assigns)
    Laravex.Http.Response.html(rendered)
  end

  def render_string(contents, assigns) do
    assigns = Map.new(assigns, fn {k, v} -> {to_string(k), v} end)

    contents
    |> apply_extends(assigns)
    |> replace_vite()
    |> replace_csrf(assigns)
    |> replace_foreach(assigns)
    |> replace_error(assigns)
    |> replace_directives(assigns)
    |> replace_echoes(assigns)
  end

  defp find_view(base, name) do
    [
      Path.join([base, "resources", "views", "#{name}.blade.php"]),
      Path.join([base, "resources", "views", "#{name}.html"]),
      Path.join([base, "resources", "views", "#{name}.eex"])
    ]
    |> Enum.find(&File.exists?/1)
  end

  defp apply_extends(contents, assigns) do
    case Regex.run(~r/@extends\(['"]([^'"]+)['"]\)/, contents) do
      [_, layout] ->
        base = Laravex.Foundation.Application.base_path()
        layout_path = find_view(base, layout)
        layout_html = if layout_path, do: File.read!(layout_path), else: "{{ content }}"

        sections =
          Regex.scan(~r/@section\(['"]([^'"]+)['"]\)(.*?)@endsection/s, contents)
          |> Map.new(fn [_, name, body] -> {name, String.trim(body)} end)

        content =
          case Regex.run(~r/@section\(['"]content['"]\)(.*?)@endsection/s, contents) do
            [_, body] -> String.trim(body)
            _ -> Regex.replace(~r/@extends\(['"][^'"]+['"]\)/, contents, "")
          end

        layout_html
        |> String.replace("@yield('content')", content)
        |> String.replace("@yield(\"content\")", content)
        |> then(fn html ->
          Enum.reduce(sections, html, fn {name, body}, acc ->
            acc
            |> String.replace("@yield('#{name}')", body)
            |> String.replace("@yield(\"#{name}\")", body)
          end)
        end)
        |> replace_echoes(assigns)

      _ ->
        contents
    end
  end

  defp replace_vite(contents) do
    Regex.replace(~r/@vite\(\[(.*?)\]\)/, contents, fn _, inner ->
      assets =
        inner
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(fn s -> String.trim(s, "'\"") end)

      Laravex.Vite.tags(assets)
    end)
  end

  defp replace_csrf(contents, assigns) do
    token =
      Map.get(assigns, "_token") ||
        Map.get(assigns, "csrf_token") ||
        "csrf-token"

    contents
    |> String.replace("@csrf", ~s(<input type="hidden" name="_token" value="#{token}">))
    |> String.replace("{{ csrf_token() }}", token)
  end

  defp replace_foreach(contents, assigns) do
    Regex.replace(~r/@foreach\s*\(\s*\$?(\w+)\s+as\s+\$?(\w+)\s*\)(.*?)@endforeach/s, contents, fn _,
                                                                                               list_key,
                                                                                               item_key,
                                                                                               body ->
      list = get_in_assign(assigns, list_key) || []

      list
      |> List.wrap()
      |> Enum.map_join(fn item ->
        item_assigns = Map.put(assigns, item_key, item)
        body |> replace_echoes(item_assigns) |> replace_directives(item_assigns)
      end)
    end)
  end

  defp replace_error(contents, assigns) do
    errors = Map.get(assigns, "errors") || Map.get(assigns, :errors) || %{}

    Regex.replace(~r/@error\(['"]([^'"]+)['"]\)(.*?)@enderror/s, contents, fn _, field, body ->
      case Map.get(errors, field) || Map.get(errors, String.to_atom(field)) do
        nil ->
          ""

        msgs ->
          msg = List.wrap(msgs) |> List.first() |> to_string()
          replace_echoes(body, Map.put(assigns, "message", msg))
      end
    end)
  end

  defp replace_directives(contents, assigns) do
    Regex.replace(~r/@if\((.*?)\)(.*?)@endif/s, contents, fn _, expr, body ->
      if truthy?(eval_expr(expr, assigns)), do: body, else: ""
    end)
  end

  defp replace_echoes(contents, assigns) do
    Regex.replace(~r/\{\{\s*\$?([a-zA-Z0-9_\.]+)\s*\}\}/, contents, fn _, key ->
      key = String.trim_leading(key, "$")
      value = get_in_assign(assigns, key)
      value |> to_string() |> html_escape()
    end)
  end

  defp get_in_assign(assigns, key) do
    parts = String.split(key, ".")

    Enum.reduce_while(parts, assigns, fn part, acc ->
      cond do
        is_map(acc) and Map.has_key?(acc, part) ->
          {:cont, Map.get(acc, part)}

        is_map(acc) and Map.has_key?(acc, String.to_atom(part)) ->
          {:cont, Map.get(acc, String.to_atom(part))}

        is_struct(acc) ->
          try do
            {:cont, Map.get(acc, String.to_atom(part))}
          rescue
            _ -> {:halt, ""}
          end

        true ->
          {:halt, ""}
      end
    end)
  end

  defp eval_expr(expr, assigns) do
    expr = String.trim(expr)

    cond do
      String.starts_with?(expr, "$") ->
        get_in_assign(assigns, String.trim_leading(expr, "$"))

      Map.has_key?(assigns, expr) ->
        Map.get(assigns, expr)

      true ->
        expr not in ["false", "null", "nil", "0", ""]
    end
  end

  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(""), do: false
  defp truthy?([]), do: false
  defp truthy?(_), do: true

  defp html_escape(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end

defmodule Laravex.Vite do
  @moduledoc "@vite helper — uses hot file or manifest / direct public paths."

  def tags(assets) when is_list(assets) do
    base = Laravex.Foundation.Application.base_path()
    hot = Path.join(base, "public/hot")

    if File.exists?(hot) do
      url = String.trim(File.read!(hot))

      Enum.map_join(assets, "\n", fn asset ->
        if String.ends_with?(asset, ".css") do
          ~s(<link rel="stylesheet" href="#{url}/#{asset}">)
        else
          ~s(<script type="module" src="#{url}/#{asset}"></script>)
        end
      end)
    else
      Enum.map_join(assets, "\n", fn asset ->
        public = "/build/" <> String.replace_leading(asset, "resources/", "")

        if String.ends_with?(asset, ".css") do
          ~s(<link rel="stylesheet" href="#{public}">)
        else
          ~s(<script type="module" src="#{public}"></script>)
        end
      end)
    end
  end
end
