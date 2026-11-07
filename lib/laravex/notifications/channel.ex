defmodule Laravex.Notifications.Notifier do
  @moduledoc "Send notifications via mail/database/log channels."

  def send(notifiable, notification) do
    channels =
      if function_exported?(notification, :via, 1) do
        notification.via(notifiable)
      else
        [:mail]
      end

    Enum.each(channels, fn
      :mail ->
        if function_exported?(notification, :to_mail, 1) do
          Laravex.Mail.Mailer.send(notification.to_mail(notifiable))
        end

      :database ->
        store_database(notifiable, notification)

      :log ->
        Laravex.Log.Logger.info("Notification", %{
          to: Map.get(notifiable, :email),
          notification: notification
        })

      _ ->
        :ok
    end)

    :ok
  end

  defp store_database(notifiable, notification) do
    dir = Path.join(Laravex.Foundation.Application.base_path(), "storage/app/notifications")
    File.mkdir_p!(dir)

    payload = %{
      notifiable_id: Map.get(notifiable, :id),
      notification: inspect(notification),
      at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    File.write!(
      Path.join(dir, "#{System.unique_integer([:positive])}.json"),
      Laravex.Support.JSON.encode!(payload)
    )
  end
end
