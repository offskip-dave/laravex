defmodule Laravex.Notifications.Notifier do
  @moduledoc "Send notifications via mail/database/log channels."

  @table :laravex_notifications_sent

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

  def send(notifiable, notification) do
    ensure()
    {notification_mod, payload} = unwrap(notification)

    channels =
      cond do
        function_exported?(notification_mod, :via, 1) ->
          notification_mod.via(notifiable)

        function_exported?(notification_mod, :via, 2) ->
          notification_mod.via(notifiable, payload)

        true ->
          [:mail]
      end

    Enum.each(List.wrap(channels), fn channel ->
      deliver(channel, notifiable, notification_mod, payload)
    end)

    if Application.get_env(:laravex, :notification_fake, false) do
      :ets.insert(@table, {:notification, %{notifiable: notifiable, notification: notification_mod, payload: payload}})
    end

    :ok
  end

  def fake do
    ensure()
    Application.put_env(:laravex, :notification_fake, true)
    :ets.delete_all_objects(@table)
    :ok
  end

  def sent do
    ensure()
    :ets.lookup(@table, :notification) |> Enum.map(fn {:notification, m} -> m end)
  end

  def assert_sent(fun) when is_function(fun, 1), do: Enum.any?(sent(), fun)

  defp unwrap({mod, payload}) when is_atom(mod), do: {mod, payload}
  defp unwrap(mod) when is_atom(mod), do: {mod, nil}

  defp deliver(:mail, notifiable, mod, payload) do
    mail =
      cond do
        function_exported?(mod, :to_mail, 2) and not is_nil(payload) ->
          mod.to_mail(notifiable, payload)

        function_exported?(mod, :to_mail, 1) ->
          if is_nil(payload), do: mod.to_mail(notifiable), else: mod.to_mail({notifiable, payload})

        true ->
          nil
      end

    if mail, do: Laravex.Mail.Mailer.send(mail)
  end

  defp deliver(:database, notifiable, mod, payload) do
    store_database(notifiable, mod, payload)
  end

  defp deliver(:log, notifiable, mod, payload) do
    Laravex.Log.Logger.info("Notification", %{
      to: route_mail(notifiable),
      notification: mod,
      payload: payload
    })
  end

  defp deliver(_, _, _, _), do: :ok

  defp route_mail(notifiable) do
    mod = notifiable.__struct__

    cond do
      function_exported?(mod, :route_notification_for_mail, 1) ->
        mod.route_notification_for_mail(notifiable)

      Map.has_key?(notifiable, :email) ->
        notifiable.email

      true ->
        nil
    end
  rescue
    _ -> Map.get(notifiable, :email)
  end

  defp store_database(notifiable, notification, payload) do
    dir = Path.join(Laravex.Foundation.Application.base_path(), "storage/app/notifications")
    File.mkdir_p!(dir)

    entry = %{
      "notifiable_id" => Map.get(notifiable, :id),
      "notifiable_type" => to_string(notifiable.__struct__),
      "notification" => to_string(notification),
      "data" => inspect(payload),
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    File.write!(
      Path.join(dir, "#{System.unique_integer([:positive])}.json"),
      Laravex.Support.JSON.encode!(entry)
    )

    if Laravex.Database.Schema.has_table?("notifications") do
      Laravex.Database.Query.insert("notifications", %{
        "id" => Laravex.Support.Helpers.str_random(36),
        "type" => to_string(notification),
        "notifiable_type" => to_string(notifiable.__struct__),
        "notifiable_id" => Map.get(notifiable, :id),
        "data" => Laravex.Support.JSON.encode!(%{"payload" => inspect(payload)}),
        "created_at" => entry["created_at"],
        "updated_at" => entry["created_at"]
      })
    end
  rescue
    _ -> :ok
  end
end

defmodule Laravex.Notifications.Notifiable do
  @moduledoc "Mixin for models that can receive notifications."

  defmacro __using__(_opts) do
    quote do
      def notify(%__MODULE__{} = model, notification) do
        Laravex.Notifications.Notifier.send(model, notification)
      end

      def route_notification_for_mail(%{email: email}), do: email
      def route_notification_for_mail(_), do: nil

      defoverridable route_notification_for_mail: 1
    end
  end
end
