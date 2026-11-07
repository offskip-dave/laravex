defmodule Laravex.Mail.Mailer do
  @moduledoc "Mail manager: log and array drivers with view rendering."

  @table :laravex_mail_array

  def ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        :ets.new(@table, [:named_table, :public, :bag])
      rescue
        ArgumentError -> :ok
      end
    end

    :ok
  end

  @supported_drivers ~w(log array)

  def send(mailable) do
    ensure()
    driver = to_string(Laravex.Config.Repository.get("mail.default", "log"))
    ensure_driver!(driver)
    message = normalize(mailable)

    if Application.get_env(:laravex, :mail_fake, false) or driver == "array" do
      :ets.insert(@table, {:mail, message})
    end

    case driver do
      "array" ->
        :ok

      "log" ->
        Laravex.Log.Logger.info("Mail sent", message)
        :ok
    end
  end

  defp ensure_driver!(driver) do
    unless driver in @supported_drivers do
      raise ArgumentError,
            "Mailer uses unsupported driver #{inspect(driver)}. " <>
              "Supported drivers: #{Enum.join(@supported_drivers, ", ")} " <>
              "(set MAIL_MAILER=log|array)."
    end

    :ok
  end

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

  defp normalize(%{to: _} = m) do
    from = Laravex.Config.Repository.get("mail.from", %{})
    body = render_body(m)

    Map.merge(
      %{
        from_address: Map.get(from, "address") || Map.get(from, :address),
        from_name: Map.get(from, "name") || Map.get(from, :name),
        body: body
      },
      Map.new(m)
    )
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
          data: if(function_exported?(mod, :data, 0), do: mod.data(), else: %{})
        }
      end

    normalize(data)
  end

  defp render_body(%{body: body}) when is_binary(body) and body != "", do: body

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
end

defmodule Laravex.Mail.Mailable do
  defmacro __using__(_opts) do
    quote do
      def send, do: Laravex.Mail.Mailer.send(__MODULE__)
      defoverridable send: 0
    end
  end
end
