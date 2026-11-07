defmodule Laravex.View do
  @moduledoc """
  Blade-like view renderer: echoes, csrf, vite, if/foreach/error,
  components/slots, push/stack, and layouts.
  """

  @shared_key :laravex_view_shared

  @doc "Share data with all views (Laravel `View::share`)."
  def share(key, value) do
    share(%{to_string(key) => value})
  end

  def share(map) when is_map(map) do
    merged = Map.merge(shared(), stringify_assigns(map))
    :persistent_term.put(@shared_key, merged)
    :ok
  end

  def shared do
    :persistent_term.get(@shared_key, %{})
  rescue
    ArgumentError -> %{}
  end

  def make(name, assigns \\ %{}) when is_binary(name) do
    Process.put(:laravex_stacks, %{})
    base = Laravex.Foundation.Application.base_path()
    path = find_view(base, name)
    unless path, do: raise("View [#{name}] not found.")

    contents =
      case Laravex.View.Cache.read(path) do
        {:ok, c} -> c
        :error -> File.read!(path)
      end

    rendered = render_string(contents, merge_shared(assigns))
    Laravex.Http.Response.html(rendered)
  end

  def render_string(contents, assigns) do
    assigns = stringify_assigns(assigns)
    Process.put(:laravex_once_keys, MapSet.new())

    {contents, verbatim} = extract_verbatim(contents)
    {contents, assigns} = apply_props(contents, assigns)
    {contents, assigns} = apply_inject(contents, assigns)
    {contents, assigns} = apply_php(contents, assigns)

    contents
    |> apply_extends(assigns)
    |> replace_includes(assigns)
    |> replace_components(assigns)
    |> replace_vite()
    |> replace_csrf(assigns)
    |> replace_method()
    |> replace_selected_checked(assigns)
    |> replace_lang()
    |> replace_push()
    |> replace_push_once()
    |> replace_prepend()
    |> replace_prepend_once()
    |> replace_auth_directives(assigns)
    |> replace_links(assigns)
    |> replace_forelse(assigns)
    |> replace_foreach(assigns)
    |> replace_error(assigns)
    |> replace_session(assigns)
    |> replace_isset_empty(assigns)
    |> replace_once(assigns)
    |> replace_class(assigns)
    |> replace_directives(assigns)
    |> replace_old(assigns)
    |> replace_json(assigns)
    |> replace_raw_echoes(assigns)
    |> replace_echoes(assigns)
    |> replace_stacks()
    |> restore_verbatim(verbatim)
  end

  defp extract_verbatim(contents) do
    {html, blocks} =
      Regex.scan(~r/@verbatim(.*?)@endverbatim/s, contents)
      |> Enum.with_index()
      |> Enum.reduce({contents, %{}}, fn {[full, body], idx}, {acc, map} ->
        token = "%%LARAVEX_VERBATIM_#{idx}%%"
        {String.replace(acc, full, token, global: false), Map.put(map, token, body)}
      end)

    {html, blocks}
  end

  defp restore_verbatim(contents, blocks) do
    Enum.reduce(blocks, contents, fn {token, body}, acc ->
      String.replace(acc, token, body)
    end)
  end

  defp replace_isset_empty(contents, assigns) do
    contents
    |> then(fn html ->
      Regex.replace(~r/@isset\(\s*\$?([a-zA-Z0-9_\.]+)\s*\)(.*?)@endisset/s, html, fn _, key, body ->
        key = String.trim_leading(key, "$")
        if assign_present?(assigns, key), do: body, else: ""
      end)
    end)
    |> then(fn html ->
      Regex.replace(~r/@empty\(\s*\$?([a-zA-Z0-9_\.]+)\s*\)(.*?)@endempty/s, html, fn _, key, body ->
        key = String.trim_leading(key, "$")
        value = get_in_assign(assigns, key)
        if blank_assign?(value), do: body, else: ""
      end)
    end)
  end

  defp replace_once(contents, _assigns) do
    Regex.replace(~r/@once(.*?)@endonce/s, contents, fn _, body ->
      keys = Process.get(:laravex_once_keys, MapSet.new())
      hash = :erlang.phash2(body)

      if MapSet.member?(keys, hash) do
        ""
      else
        Process.put(:laravex_once_keys, MapSet.put(keys, hash))
        body
      end
    end)
  end

  defp replace_class(contents, assigns) do
    Regex.replace(~r/@class\(\[(.*?)\]\)/s, contents, fn _, inner ->
      classes =
        inner
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.flat_map(fn part ->
          case String.split(part, "=>", parts: 2) do
            [class_expr, cond_expr] ->
              class_name = unwrap_class_literal(String.trim(class_expr))

              if truthy?(eval_expr(String.trim(cond_expr), assigns)) do
                [class_name]
              else
                []
              end

            [class_expr] ->
              [unwrap_class_literal(String.trim(class_expr))]
          end
        end)
        |> Enum.reject(&(&1 == ""))

      ~s(class="#{Enum.join(classes, " ")}")
    end)
  end

  defp unwrap_class_literal("'" <> rest), do: String.trim_trailing(rest, "'")
  defp unwrap_class_literal("\"" <> rest), do: String.trim_trailing(rest, "\"")
  defp unwrap_class_literal(other), do: other

  defp assign_present?(assigns, key) do
    parts = String.split(key, ".")
    {last, parents} = List.pop_at(parts, -1)

    parent =
      Enum.reduce_while(parents, assigns, fn part, acc ->
        cond do
          is_map(acc) and Map.has_key?(acc, part) -> {:cont, Map.get(acc, part)}
          is_map(acc) and Map.has_key?(acc, String.to_atom(part)) ->
            {:cont, Map.get(acc, String.to_atom(part))}
          true -> {:halt, :__missing__}
        end
      end)

    cond do
      parent == :__missing__ -> false
      is_map(parent) -> Map.has_key?(parent, last) or Map.has_key?(parent, String.to_atom(last))
      true -> false
    end
  end

  defp blank_assign?(nil), do: true
  defp blank_assign?(""), do: true
  defp blank_assign?([]), do: true
  defp blank_assign?(%{} = m), do: map_size(m) == 0
  defp blank_assign?(_), do: false

  defp merge_shared(assigns) do
    request_shared =
      case Process.get(:laravex_request) do
        %{errors: errors, old: old, flash: flash, session: session} ->
          %{
            "errors" => errors || %{},
            "old" => old || %{},
            "flash" => flash || %{},
            "_token" => Map.get(session || %{}, "_token"),
            "csrf_token" => Map.get(session || %{}, "_token")
          }

        %{errors: errors, old: old, session: session} ->
          %{
            "errors" => errors || %{},
            "old" => old || %{},
            "flash" => %{},
            "_token" => Map.get(session || %{}, "_token"),
            "csrf_token" => Map.get(session || %{}, "_token")
          }

        _ ->
          %{}
      end

    shared()
    |> Map.merge(request_shared)
    |> Map.merge(stringify_assigns(assigns))
  end

  defp stringify_assigns(assigns) when is_map(assigns) do
    Map.new(assigns, fn {k, v} -> {to_string(k), v} end)
  end

  defp find_view(base, name) do
    [
      Path.join([base, "resources", "views", "#{name}.blade.php"]),
      Path.join([base, "resources", "views", "components", "#{name}.blade.php"]),
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

        parent_sections =
          Regex.scan(~r/@section\(['"]([^'"]+)['"]\)(.*?)@endsection/s, layout_html)
          |> Map.new(fn [_, name, body] -> {name, String.trim(body)} end)

        Process.put(:laravex_parent_sections, parent_sections)

        sections =
          Regex.scan(~r/@section\(['"]([^'"]+)['"]\)(.*?)@endsection/s, contents)
          |> Map.new(fn [_, name, body] ->
            body =
              String.trim(body)
              |> String.replace("@parent", Map.get(parent_sections, name, ""))

            {name, body}
          end)

        content =
          case Map.get(sections, "content") do
            body when is_binary(body) -> body
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

  defp replace_components(contents, assigns) do
    Regex.replace(
      ~r/@component\(['"]([^'"]+)['"](?:,\s*(\[.*?\]))?\)(.*?)@endcomponent/s,
      contents,
      fn _, name, attrs_src, inner ->
        slots =
          Regex.scan(~r/@slot\(['"]([^'"]+)['"]\)(.*?)@endslot/s, inner)
          |> Map.new(fn [_, slot_name, body] -> {slot_name, String.trim(body)} end)

        slot =
          Regex.replace(~r/@slot\(['"][^'"]+['"]\).*?@endslot/s, inner, "")
          |> String.trim()

        component_assigns =
          assigns
          |> Map.merge(parse_attrs(attrs_src, assigns))
          |> Map.put("slot", slot)
          |> Map.merge(Map.new(slots, fn {k, v} -> {k, v} end))

        base = Laravex.Foundation.Application.base_path()

        path =
          find_view(base, name) ||
            find_view(base, "components/#{name}")

        if path do
          stack = Process.get(:laravex_component_stack, [])
          Process.put(:laravex_component_stack, [assigns | stack])

          try do
            File.read!(path)
            |> then(fn html ->
              {html, component_assigns} = apply_props(html, component_assigns)
              {html, component_assigns} = apply_aware(html, component_assigns)

              html
              |> String.replace("{{ $slot }}", slot)
              |> String.replace("{{ slot }}", slot)
              |> replace_foreach(component_assigns)
              |> replace_error(component_assigns)
              |> replace_directives(component_assigns)
              |> replace_echoes(component_assigns)
            end)
          after
            Process.put(:laravex_component_stack, stack)
          end
        else
          "<!-- missing component #{name} -->"
        end
      end
    )
  end

  # @props(['type' => 'info', 'message']) — declare defaults / required keys.
  defp apply_props(contents, assigns) do
    case Regex.run(~r/@props\(\[(.*?)\]\)/s, contents) do
      [full, inner] ->
        defaults = parse_props_list(inner, assigns)

        merged =
          Enum.reduce(defaults, assigns, fn {k, default}, acc ->
            cond do
              Map.has_key?(acc, k) -> acc
              Map.has_key?(acc, String.to_atom(k)) -> Map.put(acc, k, Map.get(acc, String.to_atom(k)))
              true -> Map.put(acc, k, default)
            end
          end)

        {String.replace(contents, full, "", global: false), merged}

      _ ->
        {contents, assigns}
    end
  end

  defp apply_inject(contents, assigns) do
    case Regex.run(~r/@inject\(\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]+)['"]\s*\)/, contents) do
      [full, var, mod_str] ->
        value = resolve_inject(mod_str)
        apply_inject(String.replace(contents, full, "", global: false), Map.put(assigns, var, value))

      nil ->
        {contents, assigns}
    end
  end

  defp resolve_inject(mod_str) do
    mod = module_from_string(mod_str)

    try do
      Laravex.Container.make(mod)
    rescue
      _ -> fallback_inject(mod)
    catch
      :exit, _ -> fallback_inject(mod)
    end
  end

  defp fallback_inject(mod) when is_atom(mod) do
    cond do
      function_exported?(mod, :new, 0) -> mod.new()
      function_exported?(mod, :new, 1) -> mod.new([])
      true -> mod
    end
  end

  defp module_from_string(mod_str) do
    mod_str
    |> String.split(".")
    |> Module.safe_concat()
  rescue
    ArgumentError -> String.to_atom("Elixir." <> mod_str)
  end

  defp apply_php(contents, assigns) do
    case Regex.run(~r/@php(.*?)@endphp/s, contents) do
      [full, body] ->
        assigns = eval_php_block(String.trim(body), assigns)
        apply_php(String.replace(contents, full, "", global: false), assigns)

      nil ->
        {contents, assigns}
    end
  end

  defp eval_php_block("", assigns), do: assigns

  defp eval_php_block(body, assigns) do
    elixir =
      body
      |> String.split(~r/\r?\n/, trim: false)
      |> Enum.map(&convert_php_assign_line/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    code = if elixir == "", do: "assigns", else: elixir <> "\nassigns"

    try do
      {result, _} = Code.eval_string(code, [assigns: assigns], __ENV__)
      if is_map(result), do: result, else: assigns
    rescue
      _ -> assigns
    catch
      _, _ -> assigns
    end
  end

  defp convert_php_assign_line(line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" or String.starts_with?(trimmed, "//") or String.starts_with?(trimmed, "#") ->
        ""

      true ->
        case Regex.run(~r/^assigns\[\s*"([^"]+)"\s*\]\s*=\s*(.+)$/u, trimmed) ||
               Regex.run(~r/^assigns\[\s*'([^']+)'\s*\]\s*=\s*(.+)$/u, trimmed) do
          [_, key, expr] ->
            "assigns = Map.put(assigns, \"#{key}\", #{String.trim(expr)})"

          nil ->
            trimmed
        end
    end
  end

  # @aware(['user']) — pull missing keys from the parent component assigns.
  defp apply_aware(contents, assigns) do
    case Regex.run(~r/@aware\(\[(.*?)\]\)/s, contents) do
      [full, inner] ->
        keys =
          Regex.scan(~r/['"](\w+)['"]/, inner)
          |> Enum.map(fn [_, k] -> k end)

        parent = Process.get(:laravex_component_stack, []) |> List.first() || %{}

        merged =
          Enum.reduce(keys, assigns, fn k, acc ->
            cond do
              Map.has_key?(acc, k) and not is_nil(Map.get(acc, k)) ->
                acc

              Map.has_key?(parent, k) ->
                Map.put(acc, k, Map.get(parent, k))

              Map.has_key?(parent, String.to_atom(k)) ->
                Map.put(acc, k, Map.get(parent, String.to_atom(k)))

              true ->
                acc
            end
          end)

        {String.replace(contents, full, "", global: false), merged}

      _ ->
        {contents, assigns}
    end
  end

  defp parse_props_list(inner, assigns) when is_binary(inner) do
    Regex.scan(
      ~r/['"](\w+)['"](?:\s*=>\s*(?:['"]([^'"]*)['"]|(\$[a-zA-Z0-9_\.]+)|(true|false|null)|(-?\d+(?:\.\d+)?)))?/,
      inner
    )
    |> Enum.map(fn
      [_, k] ->
        {k, nil}

      [_, k, str, "", "", ""] ->
        {k, str}

      [_, k, "", var, "", ""] ->
        key = String.trim_leading(var, "$")
        {k, get_in_assign(assigns, key)}

      [_, k, "", "", "true", ""] ->
        {k, true}

      [_, k, "", "", "false", ""] ->
        {k, false}

      [_, k, "", "", "null", ""] ->
        {k, nil}

      [_, k, "", "", "", num] ->
        {k,
         case Integer.parse(num) do
           {i, ""} ->
             i

           _ ->
             case Float.parse(num) do
               {f, ""} -> f
               _ -> num
             end
         end}

      [_, k | _] ->
        {k, nil}
    end)
    |> Map.new()
  end

  defp parse_attrs(nil, _), do: %{}
  defp parse_attrs("", _), do: %{}

  defp parse_attrs(src, assigns) do
    # Supports: 'type' => 'error', "n" => 1, 'ok' => true, 'user' => $user
    Regex.scan(
      ~r/['"](\w+)['"]\s*=>\s*(?:['"]([^'"]*)['"]|(\$[a-zA-Z0-9_\.]+)|(true|false|null)|(-?\d+(?:\.\d+)?))/,
      src || ""
    )
    |> Map.new(fn
      [_, k, str, "", "", ""] ->
        {k, str}

      [_, k, "", var, "", ""] ->
        key = String.trim_leading(var, "$")
        {k, get_in_assign(assigns, key)}

      [_, k, "", "", "true", ""] ->
        {k, true}

      [_, k, "", "", "false", ""] ->
        {k, false}

      [_, k, "", "", "null", ""] ->
        {k, nil}

      [_, k, "", "", "", num] ->
        {k,
         case Integer.parse(num) do
           {i, ""} -> i
           _ ->
             case Float.parse(num) do
               {f, ""} -> f
               _ -> num
             end
         end}

      [_, k | _] ->
        {k, ""}
    end)
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

  defp replace_method(contents) do
    Regex.replace(~r/@method\(['"]([^'"]+)['"]\)/, contents, fn _, method ->
      ~s(<input type="hidden" name="_method" value="#{String.upcase(method)}">)
    end)
  end

  defp replace_selected_checked(contents, assigns) do
    contents
    |> then(fn html ->
      Regex.replace(~r/@selected\(\s*(.+?)\s*\)/, html, fn _, expr ->
        if truthy?(eval_form_compare(expr, assigns)), do: "selected", else: ""
      end)
    end)
    |> then(fn html ->
      Regex.replace(~r/@checked\(\s*(.+?)\s*\)/, html, fn _, expr ->
        if truthy?(eval_form_compare(expr, assigns)), do: "checked", else: ""
      end)
    end)
    |> then(fn html ->
      Regex.replace(~r/@disabled\(\s*(.+?)\s*\)/, html, fn _, expr ->
        if truthy?(eval_form_compare(expr, assigns)), do: "disabled", else: ""
      end)
    end)
    |> then(fn html ->
      Regex.replace(~r/@readonly\(\s*(.+?)\s*\)/, html, fn _, expr ->
        if truthy?(eval_form_compare(expr, assigns)), do: "readonly", else: ""
      end)
    end)
    |> then(fn html ->
      Regex.replace(~r/@required\(\s*(.+?)\s*\)/, html, fn _, expr ->
        if truthy?(eval_form_compare(expr, assigns)), do: "required", else: ""
      end)
    end)
  end

  # Supports `old('field') == 'value'` and bare assign truthiness.
  defp eval_form_compare(expr, assigns) do
    expr = String.trim(expr)

    cond do
      String.contains?(expr, "==") ->
        [left, right] = String.split(expr, "==", parts: 2)
        left_v = eval_form_side(String.trim(left), assigns)
        right_v = eval_form_side(String.trim(right), assigns)
        to_string(left_v) == to_string(right_v)

      true ->
        eval_expr(expr, assigns)
    end
  end

  defp eval_form_side("old('" <> rest, _assigns) do
    key = rest |> String.trim_trailing("')") |> String.trim_trailing("\")")
    Laravex.Support.Helpers.old(key, "")
  end

  defp eval_form_side("old(\"" <> rest, _assigns) do
    key = String.trim_trailing(rest, "\")")
    Laravex.Support.Helpers.old(key, "")
  end

  defp eval_form_side("'" <> rest, _assigns), do: String.trim_trailing(rest, "'")
  defp eval_form_side("\"" <> rest, _assigns), do: String.trim_trailing(rest, "\"")
  defp eval_form_side(expr, assigns), do: eval_expr(expr, assigns)

  defp replace_lang(contents) do
    contents
    |> then(fn html ->
      Regex.replace(~r/@lang\(['"]([^'"]+)['"]\)/, html, fn _, key ->
        Laravex.Translation.get(key) |> html_escape()
      end)
    end)
    |> then(fn html ->
      Regex.replace(~r/\{\{\s*__\(['"]([^'"]+)['"]\)\s*\}\}/, html, fn _, key ->
        Laravex.Translation.get(key) |> html_escape()
      end)
    end)
  end

  defp replace_includes(contents, assigns) do
    contents
    |> replace_include_if(assigns)
    |> replace_include_when(assigns)
    |> replace_include_unless(assigns)
    |> replace_include_plain(assigns)
  end

  defp replace_include_plain(contents, assigns) do
    Regex.replace(~r/@include\(['"]([^'"]+)['"](?:,\s*(\[.*?\]))?\)/, contents, fn _, name, attrs_src ->
      render_include(name, attrs_src, assigns, missing: :comment)
    end)
  end

  # @includeIf('view') — include only when the view file exists.
  defp replace_include_if(contents, assigns) do
    Regex.replace(
      ~r/@includeIf\(['"]([^'"]+)['"](?:,\s*(\[.*?\]))?\)/,
      contents,
      fn _, name, attrs_src ->
        render_include(name, attrs_src, assigns, missing: :empty)
      end
    )
  end

  # @includeWhen($cond, 'view') / @includeUnless($cond, 'view')
  defp replace_include_when(contents, assigns) do
    Regex.replace(
      ~r/@includeWhen\(\s*(.+?)\s*,\s*['"]([^'"]+)['"](?:,\s*(\[.*?\]))?\)/,
      contents,
      fn _, expr, name, attrs_src ->
        if truthy?(eval_expr(expr, assigns)),
          do: render_include(name, attrs_src, assigns, missing: :comment),
          else: ""
      end
    )
  end

  defp replace_include_unless(contents, assigns) do
    Regex.replace(
      ~r/@includeUnless\(\s*(.+?)\s*,\s*['"]([^'"]+)['"](?:,\s*(\[.*?\]))?\)/,
      contents,
      fn _, expr, name, attrs_src ->
        if truthy?(eval_expr(expr, assigns)),
          do: "",
          else: render_include(name, attrs_src, assigns, missing: :comment)
      end
    )
  end

  defp render_include(name, attrs_src, assigns, opts) do
    base = Laravex.Foundation.Application.base_path()
    path = find_view(base, name)

    cond do
      path ->
        File.read!(path)
        |> render_string(Map.merge(assigns, parse_attrs(attrs_src, assigns)))

      Keyword.get(opts, :missing) == :empty ->
        ""

      true ->
        "<!-- missing include #{name} -->"
    end
  end

  defp replace_old(contents, assigns) do
    old = Map.get(assigns, "old") || %{}

    Regex.replace(
      ~r/\{\{\s*old\(['"]([^'"]+)['"](?:,\s*(?:['"]([^'"]*)['"]|\$?(\w+)))?\)\s*\}\}/,
      contents,
      fn _, key, default_lit, default_var ->
        default =
          cond do
            is_binary(default_lit) and default_lit != "" -> default_lit
            is_binary(default_var) and default_var != "" -> get_in_assign(assigns, default_var)
            true -> ""
          end

        value = Map.get(old, key) || Map.get(old, String.to_atom(key)) || default || ""
        value |> to_string() |> html_escape()
      end
    )
  end

  defp replace_session(contents, assigns) do
    flash = Map.get(assigns, "flash") || %{}

    Regex.replace(~r/@session\(['"]([^'"]+)['"]\)(.*?)@endsession/s, contents, fn _, key, body ->
      case Map.get(flash, key) || Map.get(flash, String.to_atom(key)) do
        nil -> ""
        value -> replace_echoes(body, Map.put(assigns, "value", value))
      end
    end)
  end

  defp replace_push(contents) do
    Regex.replace(~r/@push\(['"]([^'"]+)['"]\)(.*?)@endpush/s, contents, fn _, stack, body ->
      push_stack(stack, String.trim(body), :append)
      ""
    end)
  end

  defp replace_push_once(contents) do
    Regex.replace(~r/@pushOnce\(['"]([^'"]+)['"]\)(.*?)@endPushOnce/s, contents, fn _, stack, body ->
      body = String.trim(body)
      once_key = {:laravex_push_once, stack, :erlang.phash2(body)}
      seen = Process.get(:laravex_push_once, MapSet.new())

      unless MapSet.member?(seen, once_key) do
        Process.put(:laravex_push_once, MapSet.put(seen, once_key))
        push_stack(stack, body, :append)
      end

      ""
    end)
  end

  defp replace_prepend(contents) do
    Regex.replace(~r/@prepend\(['"]([^'"]+)['"]\)(.*?)@endprepend/s, contents, fn _, stack, body ->
      push_stack(stack, String.trim(body), :prepend)
      ""
    end)
  end

  defp replace_prepend_once(contents) do
    Regex.replace(~r/@prependOnce\(['"]([^'"]+)['"]\)(.*?)@endPrependOnce/s, contents, fn _, stack, body ->
      body = String.trim(body)
      once_key = {:laravex_prepend_once, stack, :erlang.phash2(body)}
      seen = Process.get(:laravex_prepend_once, MapSet.new())

      unless MapSet.member?(seen, once_key) do
        Process.put(:laravex_prepend_once, MapSet.put(seen, once_key))
        push_stack(stack, body, :prepend)
      end

      ""
    end)
  end

  defp push_stack(stack, body, mode) do
    stacks = Process.get(:laravex_stacks, %{})
    list = Map.get(stacks, stack, [])

    list =
      case mode do
        :append -> list ++ [body]
        :prepend -> [body | list]
      end

    Process.put(:laravex_stacks, Map.put(stacks, stack, list))
  end

  defp replace_stacks(contents) do
    stacks = Process.get(:laravex_stacks, %{})

    Regex.replace(~r/@stack\(['"]([^'"]+)['"]\)/, contents, fn _, name ->
      stacks |> Map.get(name, []) |> Enum.join("\n")
    end)
  end

  defp replace_links(contents, assigns) do
    Regex.replace(~r/@links\(\s*\$?([a-zA-Z0-9_\.]+)\s*\)/, contents, fn _, key ->
      key = String.trim_leading(key, "$")
      pager = get_in_assign(assigns, key)

      cond do
        is_map(pager) and (Map.has_key?(pager, :links) or Map.has_key?(pager, "links")) ->
          Map.get(pager, :links) || Map.get(pager, "links") || ""

        is_map(pager) ->
          Laravex.Http.Paginator.links(pager)

        true ->
          ""
      end
    end)
  end

  defp replace_forelse(contents, assigns) do
    Regex.replace(
      ~r/@forelse\s*\(\s*\$?(\w+)\s+as\s+\$?(\w+)\s*\)(.*?)@empty(.*?)@endforelse/s,
      contents,
      fn _, list_key, item_key, body, empty ->
        list = get_in_assign(assigns, list_key) || []

        case List.wrap(list) do
          [] ->
            empty

          items ->
            Enum.map_join(items, fn item ->
              item_assigns = Map.put(assigns, item_key, item)
              body |> replace_echoes(item_assigns) |> replace_directives(item_assigns)
            end)
        end
      end
    )
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

  defp replace_auth_directives(contents, assigns) do
    request = Process.get(:laravex_request)
    user = if request, do: Laravex.Auth.Guard.user(request), else: Map.get(assigns, "user")
    authenticated? = not is_nil(user)

    contents
    |> then(fn html ->
      Regex.replace(~r/@auth(.*?)@endauth/s, html, fn _, body ->
        if authenticated?, do: body, else: ""
      end)
    end)
    |> then(fn html ->
      Regex.replace(~r/@guest(.*?)@endguest/s, html, fn _, body ->
        if authenticated?, do: "", else: body
      end)
    end)
    |> then(fn html ->
      Regex.replace(
        ~r/@can\(['"]([^'"]+)['"](?:,\s*\$?(\w+))?\)(.*?)@endcan/s,
        html,
        fn _, ability, resource_key, body ->
          resource =
            if resource_key in [nil, ""] do
              nil
            else
              get_in_assign(assigns, resource_key)
            end

          if user && Laravex.Auth.Gate.allows?(user, ability, resource), do: body, else: ""
        end
      )
    end)
    |> then(fn html ->
      Regex.replace(
        ~r/@cannot\(['"]([^'"]+)['"](?:,\s*\$?(\w+))?\)(.*?)@endcannot/s,
        html,
        fn _, ability, resource_key, body ->
          resource =
            if resource_key in [nil, ""] do
              nil
            else
              get_in_assign(assigns, resource_key)
            end

          if user && Laravex.Auth.Gate.allows?(user, ability, resource), do: "", else: body
        end
      )
    end)
  end

  defp replace_error(contents, assigns) do
    errors = Map.get(assigns, "errors") || %{}

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
    contents
    |> then(fn html ->
      parent_sections = Process.get(:laravex_parent_sections, %{})

      Regex.replace(~r/@parent\b/, html, fn _ ->
        Map.get(parent_sections, "content", "")
      end)
    end)
    |> then(fn html ->
      Regex.replace(~r/@unless\((.*?)\)(.*?)@endunless/s, html, fn _, expr, body ->
        if truthy?(eval_expr(expr, assigns)), do: "", else: body
      end)
    end)
    |> then(fn html ->
      Regex.replace(~r/@switch\((.*?)\)(.*?)@endswitch/s, html, fn _, expr, body ->
        evaluate_switch(expr, body, assigns)
      end)
    end)
    |> then(fn html ->
      Regex.replace(~r/@if\((.*?)\)(.*?)@endif/s, html, fn _, expr, body ->
        evaluate_if_chain(expr, body, assigns)
      end)
    end)
  end

  defp evaluate_switch(expr, body, assigns) do
    switch_val = eval_expr(String.trim(expr), assigns)

    cases =
      Regex.scan(~r/@case\((.*?)\)(.*?)(?=@case\(|@default|\z)/s, body)

    default =
      case Regex.run(~r/@default(.*)\z/s, body) do
        [_, content] -> strip_break(content)
        _ -> ""
      end

    Enum.find_value(cases, default, fn [_, case_expr, content] ->
      case_val = eval_expr(String.trim(case_expr), assigns)

      if values_equal?(case_val, switch_val) do
        strip_break(content)
      else
        nil
      end
    end)
  end

  defp strip_break(content) when is_binary(content) do
    content
    |> String.replace(~r/@break\s*/, "")
    |> String.trim()
  end

  defp values_equal?(a, b), do: a == b or to_string(a) == to_string(b)

  defp evaluate_if_chain(first_expr, body, assigns) do
    segments =
      Regex.split(~r/@(elseif\([^)]+\)|else)/, body, include_captures: true, trim: false)

    # segments: [before_elseif_or_else, capture, after, capture, after, ...]
    initial = [{first_expr, Enum.at(segments, 0) || ""}]

    branches =
      segments
      |> Enum.drop(1)
      |> Enum.chunk_every(2)
      |> Enum.reduce(initial, fn
        ["elseif(" <> rest, content], acc ->
          expr = String.trim_trailing(rest, ")")
          acc ++ [{expr, content}]

        ["else", content], acc ->
          acc ++ [{:else, content}]

        _, acc ->
          acc
      end)

    Enum.find_value(branches, "", fn
      {:else, content} -> content
      {expr, content} -> if truthy?(eval_expr(expr, assigns)), do: content, else: nil
    end)
  end

  defp replace_json(contents, assigns) do
    Regex.replace(~r/@json\(\s*\$?([a-zA-Z0-9_\.]+)\s*\)/, contents, fn _, key ->
      key = String.trim_leading(key, "$")
      value = get_in_assign(assigns, key)
      value |> Laravex.Support.JSON.encode!() |> json_for_html()
    end)
  end

  defp replace_raw_echoes(contents, assigns) do
    Regex.replace(~r/\{!!\s*\$?([a-zA-Z0-9_\.]+)\s*!!\}/, contents, fn _, key ->
      key = String.trim_leading(key, "$")
      get_in_assign(assigns, key) |> to_string()
    end)
  end

  defp replace_echoes(contents, assigns) do
    Regex.replace(~r/\{\{\s*\$?([a-zA-Z0-9_\.]+)\s*\}\}/, contents, fn _, key ->
      key = String.trim_leading(key, "$")
      value = get_in_assign(assigns, key)
      value |> to_string() |> html_escape()
    end)
  end

  # Make JSON safe to embed in HTML/script tags (Laravel Js::from-lite).
  defp json_for_html(json) when is_binary(json) do
    json
    |> String.replace("<", "\\u003c")
    |> String.replace(">", "\\u003e")
    |> String.replace("&", "\\u0026")
    |> String.replace("\u2028", "\\u2028")
    |> String.replace("\u2029", "\\u2029")
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

      match?({_n, ""}, Integer.parse(expr)) ->
        {n, ""} = Integer.parse(expr)
        n

      (String.starts_with?(expr, "'") and String.ends_with?(expr, "'")) or
          (String.starts_with?(expr, "\"") and String.ends_with?(expr, "\"")) ->
        String.slice(expr, 1, String.length(expr) - 2)

      expr in ["true", "TRUE"] ->
        true

      expr in ["false", "FALSE", "null", "nil", "0", ""] ->
        false

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
