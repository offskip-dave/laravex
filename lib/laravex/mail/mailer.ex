defmodule Laravex.Mail.Mailer do
  @moduledoc "Mail manager: log and array drivers with view rendering."

  @table :laravex_mail_array

  def ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        _ = :ets.new(@table, [:named_table, :public, :bag])
        :ok
      rescue
        ArgumentError -> :ok
      end
    else
      :ok
    end
  end

  def send(mailable) do
    if queue_mailable?(mailable) do
      Laravex.Mail.SendMailJob.dispatch([mailable])
      :ok
    else
      deliver_now(mailable)
    end
  end

  @doc "Send immediately (used by `SendMailJob` and sync delivery)."
  def deliver_now(mailable) do
    ensure()
    driver = to_string(Laravex.Config.Repository.get("mail.default", "log"))
    transport = Laravex.Mail.Resolver.module(driver)
    message = normalize(mailable)

    if Application.get_env(:laravex, :mail_fake, false) or driver == "array" do
      :ets.insert(@table, {:mail, message})
    end

    transport.send(message)
  end

  defp queue_mailable?(mod) when is_atom(mod) do
    cond do
      function_exported?(mod, :via_queue?, 0) and mod.via_queue?() -> true
      function_exported?(mod, :queue?, 0) and mod.queue?() -> true
      true -> false
    end
  end

  defp queue_mailable?(_), do: false

  def sent do
    ensure()
    :ets.lookup(@table, :mail) |> Enum.map(fn {:mail, m} -> m end)
  end

  def fake do
    ensure()
    Application.put_env(:laravex, :mail_fake, true)
    :ets.delete_all_objects(@table)
    :ok
  end

  def assert_sent(fun) when is_function(fun, 1) do
    Enum.any?(sent(), fun)
  end

  def assert_not_sent(fun) when is_function(fun, 1) do
    not Enum.any?(sent(), fun)
  end

  @doc "Attach a file path to a mailable map (Laravel `$mailable->attach`)."
  def attach(%{} = message, path, opts \\ []) when is_binary(path) do
    att = %{
      path: path,
      name: Keyword.get(opts, :as) || Keyword.get(opts, :name) || Path.basename(path),
      mime: Keyword.get(opts, :mime) || Keyword.get(opts, :mime_type)
    }

    Map.update(message, :attachments, [att], fn list -> List.wrap(list) ++ [att] end)
  end

  @doc "Attach raw data as a named file (Laravel `$mailable->attachData`)."
  def attach_data(%{} = message, data, name, opts \\ [])
      when is_binary(data) and is_binary(name) do
    att = %{
      data: data,
      name: name,
      mime: Keyword.get(opts, :mime) || Keyword.get(opts, :mime_type)
    }

    Map.update(message, :attachments, [att], fn list -> List.wrap(list) ++ [att] end)
  end

  @doc "Set/merge CC recipients on a mailable map (Laravel `$mailable->cc`)."
  def cc(%{} = message, addresses), do: put_addresses(message, :cc, addresses)

  @doc "Set/merge BCC recipients on a mailable map (Laravel `$mailable->bcc`)."
  def bcc(%{} = message, addresses), do: put_addresses(message, :bcc, addresses)

  @doc "Set reply-to on a mailable map (Laravel `$mailable->replyTo`)."
  def reply_to(%{} = message, address), do: Map.put(message, :reply_to, address)

  defp put_addresses(%{} = message, key, addresses) do
    incoming = List.wrap(addresses)
    existing = List.wrap(Map.get(message, key))
    Map.put(message, key, existing ++ incoming)
  end

  defp normalize(%{to: _} = m) do
    from = Laravex.Config.Repository.get("mail.from", %{})
    body = render_body(m)
    raw = Map.new(m)

    attachments =
      normalize_attachments(Map.get(raw, :attachments) || Map.get(raw, "attachments"))

    Map.merge(
      %{
        from_address: Map.get(from, "address") || Map.get(from, :address),
        from_name: Map.get(from, "name") || Map.get(from, :name),
        body: body,
        cc: Map.get(raw, :cc) || Map.get(raw, "cc"),
        bcc: Map.get(raw, :bcc) || Map.get(raw, "bcc"),
        reply_to: Map.get(raw, :reply_to) || Map.get(raw, "reply_to") || Map.get(raw, :replyTo),
        attachments: attachments
      },
      Map.drop(raw, [:attachments, "attachments"])
    )
    |> Map.put(:attachments, attachments)
  end

  defp normalize(mod) when is_atom(mod) do
    data =
      if function_exported?(mod, :build, 0) do
        mod.build()
      else
        %{
          to: apply(mod, :to, []),
          subject: apply(mod, :subject, []),
          body: if(function_exported?(mod, :content, 0), do: mod.content(), else: ""),
          view: if(function_exported?(mod, :view, 0), do: mod.view(), else: nil),
          data: if(function_exported?(mod, :data, 0), do: mod.data(), else: %{}),
          cc: if(function_exported?(mod, :cc, 0), do: mod.cc(), else: nil),
          bcc: if(function_exported?(mod, :bcc, 0), do: mod.bcc(), else: nil),
          reply_to: if(function_exported?(mod, :reply_to, 0), do: mod.reply_to(), else: nil),
          attachments:
            if(function_exported?(mod, :attachments, 0), do: mod.attachments(), else: []),
          markdown:
            if(function_exported?(mod, :markdown, 0), do: mod.markdown(), else: nil)
        }
      end

    normalize(data)
  end

  defp normalize_attachments(nil), do: []
  defp normalize_attachments(list) when is_list(list) do
    Enum.map(list, fn
      %{path: path} = att when is_binary(path) ->
        %{
          path: path,
          name: Map.get(att, :name) || Map.get(att, "name") || Path.basename(path),
          mime: Map.get(att, :mime) || Map.get(att, "mime") || Map.get(att, :mime_type)
        }

      %{data: data} = att when is_binary(data) ->
        %{
          data: data,
          name: Map.get(att, :name) || Map.get(att, "name") || "attachment",
          mime: Map.get(att, :mime) || Map.get(att, "mime") || Map.get(att, :mime_type)
        }

      path when is_binary(path) ->
        %{path: path, name: Path.basename(path), mime: nil}

      other when is_map(other) ->
        cond do
          is_binary(Map.get(other, :data) || Map.get(other, "data")) ->
            %{
              data: Map.get(other, :data) || Map.get(other, "data"),
              name: Map.get(other, :name) || Map.get(other, "name") || "attachment",
              mime: Map.get(other, :mime) || Map.get(other, "mime")
            }

          true ->
            path = Map.get(other, :path) || Map.get(other, "path")
            %{path: path, name: Map.get(other, :name) || Map.get(other, "name"), mime: Map.get(other, :mime)}
        end

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_attachments(other), do: normalize_attachments(List.wrap(other))

  defp render_body(%{body: body}) when is_binary(body) and body != "", do: body

  defp render_body(%{markdown: {view, data}}) when is_binary(view) do
    case load_view_text(view) do
      nil -> ""
      text -> render_markdown(text, data || %{})
    end
  end

  defp render_body(%{markdown: md} = m) when is_binary(md) and md != "" do
    data = Map.get(m, :data, %{})

    if markdown_content?(md) do
      render_markdown(md, data)
    else
      case load_view_text(md) do
        nil -> render_markdown(md, data)
        text -> render_markdown(text, data)
      end
    end
  end

  defp render_body(%{view: view, data: data}) when is_binary(view) do
    base = Laravex.Foundation.Application.base_path()
    path =
      [
        Path.join([base, "resources", "views", "#{view}.blade.php"]),
        Path.join([base, "resources", "views", "#{view}.html"])
      ]
      |> Enum.find(&File.exists?/1)

    if path do
      Laravex.View.render_string(File.read!(path), data || %{})
    else
      ""
    end
  end

  defp render_body(_), do: ""

  defp load_view_text(view) do
    base = Laravex.Foundation.Application.base_path()

    path =
      [
        Path.join([base, "resources", "views", "#{view}.md"]),
        Path.join([base, "resources", "views", "#{view}.markdown"]),
        Path.join([base, "resources", "views", "#{view}.blade.php"]),
        Path.join([base, "resources", "views", "#{view}.html"])
      ]
      |> Enum.find(&File.exists?/1)

    if path, do: File.read!(path), else: nil
  end

  defp render_markdown(text, data) do
    text
    |> Laravex.View.render_string(data)
    |> markdown_to_html()
  end

  defp markdown_to_html(md) when is_binary(md) do
    md
    |> String.trim()
    |> String.split(~r/\n{2,}/)
    |> Enum.map(&markdown_block/1)
    |> Enum.join("\n")
  end

  defp markdown_block(block) do
    block = String.trim(block)

    cond do
      String.starts_with?(block, "### ") ->
        "<h3>#{inline_markdown(String.slice(block, 4..-1//1))}</h3>"

      String.starts_with?(block, "## ") ->
        "<h2>#{inline_markdown(String.slice(block, 3..-1//1))}</h2>"

      String.starts_with?(block, "# ") ->
        "<h1>#{inline_markdown(String.slice(block, 2..-1//1))}</h1>"

      true ->
        lines = String.split(block, "\n") |> Enum.map(&inline_markdown/1) |> Enum.join("<br>")
        "<p>#{lines}</p>"
    end
  end

  defp inline_markdown(line) do
    line
    |> escape_html()
    |> then(fn s ->
      s
      |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
      |> String.replace(~r/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/, "<em>\\1</em>")
    end)
  end

  defp markdown_content?(text) do
    String.contains?(text, "\n") or String.starts_with?(text, "#") or String.contains?(text, "**")
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end

defmodule Laravex.Mail.Mailable do
  defmacro __using__(_opts) do
    quote do
      def send, do: Laravex.Mail.Mailer.send(__MODULE__)
      defoverridable send: 0
    end
  end
end
