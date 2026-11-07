defmodule Laravex.Notifications.Notifier do
  @moduledoc "Send notifications via mail/database/log/broadcast channels."

  @table :laravex_notifications_sent

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

  def send(notifiable, notification) do
    ensure()
    {notification_mod, payload} = unwrap(notification)
    deliver_all(notifiable, notification_mod, payload)
  end

  @doc """
  Queue a notification for later delivery (Laravel `Notification::later`).

      Notifier.later(user, WelcomeNotification, 60)
  """
  def later(notifiable, notification, delay_seconds, opts \\ [])
      when is_integer(delay_seconds) and delay_seconds >= 0 do
    ensure()
    {notification_mod, payload} = unwrap(notification)

    Laravex.Queue.Worker.push(
      Laravex.Notifications.SendQueuedNotification,
      [notifiable, notification_mod, payload],
      Keyword.merge(opts, delay: delay_seconds)
    )

    :ok
  end

  def deliver_all(notifiable, notification_mod, payload) do
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
      deliver(normalize_channel(channel), notifiable, notification_mod, payload)
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

  defp normalize_channel(channel) when is_atom(channel), do: channel
  defp normalize_channel(channel) when is_binary(channel), do: String.to_atom(channel)

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
      payload: notification_array(notifiable, mod, payload)
    })
  end

  defp deliver(:broadcast, notifiable, mod, payload) do
    data = notification_array(notifiable, mod, payload)
    channel = broadcast_channel(notifiable, mod)
    event = broadcast_event(mod)
    Laravex.Broadcasting.Broadcaster.event(channel, event, data)
  end

  defp deliver(channel, _notifiable, mod, _payload) do
    raise ArgumentError,
          "Notification #{inspect(mod)} uses unsupported channel #{inspect(channel)}. " <>
            "Supported channels: :mail, :database, :log, :broadcast."
  end

  defp notification_array(notifiable, mod, payload) do
    cond do
      function_exported?(mod, :to_array, 2) and not is_nil(payload) ->
        mod.to_array(notifiable, payload)

      function_exported?(mod, :to_array, 1) ->
        mod.to_array(notifiable)

      function_exported?(mod, :to_database, 2) and not is_nil(payload) ->
        mod.to_database(notifiable, payload)

      function_exported?(mod, :to_database, 1) ->
        mod.to_database(notifiable)

      true ->
        %{
          "notification" => to_string(mod),
          "payload" => payload
        }
    end
  end

  defp broadcast_channel(notifiable, mod) do
    cond do
      function_exported?(mod, :broadcast_on, 1) ->
        List.wrap(mod.broadcast_on(notifiable)) |> List.first() || "notifications"

      function_exported?(mod, :broadcast_on, 0) ->
        List.wrap(mod.broadcast_on()) |> List.first() || "notifications"

      true ->
        "App.Models.User.#{Map.get(notifiable, :id)}"
    end
  end

  defp broadcast_event(mod) do
    if function_exported?(mod, :broadcast_as, 0),
      do: mod.broadcast_as(),
      else: mod |> Module.split() |> List.last()
  end

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
    data = notification_array(notifiable, notification, payload)
    dir = Path.join(Laravex.Foundation.Application.base_path(), "storage/app/notifications")
    File.mkdir_p!(dir)
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    entry = %{
      "notifiable_id" => Map.get(notifiable, :id),
      "notifiable_type" => to_string(notifiable.__struct__),
      "notification" => to_string(notification),
      "data" => data,
      "created_at" => now
    }

    File.write!(
      Path.join(dir, "#{System.unique_integer([:positive])}.json"),
      Laravex.Support.JSON.encode!(entry)
    )

    if Laravex.Database.Schema.has_table?("notifications") do
      Laravex.Database.Connection.execute(
        """
        INSERT INTO notifications (id, type, notifiable_type, notifiable_id, data, read_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, NULL, ?, ?)
        """,
        [
          Laravex.Support.Str.uuid(),
          to_string(notification),
          to_string(notifiable.__struct__),
          Map.get(notifiable, :id),
          Laravex.Support.JSON.encode!(data),
          now,
          now
        ]
      )
    end
  rescue
    _ -> :ok
  end
end

defmodule Laravex.Notifications.SendQueuedNotification do
  @moduledoc false
  use Laravex.Queue.Job, queue: true

  def handle([notifiable, notification_mod, payload]) do
    Laravex.Notifications.Notifier.deliver_all(notifiable, notification_mod, payload)
  end
end

defmodule Laravex.Notifications.Notifiable do
  @moduledoc "Mixin for models that can receive notifications (inbox helpers included)."

  defmacro __using__(_opts) do
    quote do
      def notify(%__MODULE__{} = model, notification) do
        Laravex.Notifications.Notifier.send(model, notification)
      end

      def notify_later(%__MODULE__{} = model, notification, delay_seconds, opts \\ []) do
        Laravex.Notifications.Notifier.later(model, notification, delay_seconds, opts)
      end

      def notifications(%__MODULE__{} = model) do
        Laravex.Notifications.Notifiable.notifications_for(model)
      end

      def unread_notifications(%__MODULE__{} = model) do
        Laravex.Notifications.Notifiable.unread_for(model)
      end

      def read_notifications(%__MODULE__{} = model) do
        Laravex.Notifications.Notifiable.read_for(model)
      end

      def mark_notification_as_read(%__MODULE__{} = model, id) do
        Laravex.Notifications.Notifiable.mark_as_read(model, id)
      end

      def mark_notification_as_unread(%__MODULE__{} = model, id) do
        Laravex.Notifications.Notifiable.mark_as_unread(model, id)
      end

      def mark_notifications_as_read(%__MODULE__{} = model) do
        Laravex.Notifications.Notifiable.mark_all_as_read(model)
      end

      def route_notification_for_mail(%{email: email}), do: email
      def route_notification_for_mail(_), do: nil

      defoverridable route_notification_for_mail: 1
    end
  end

  def notifications_for(%{__struct__: mod, id: id}) do
    query_for(mod, id)
    |> Laravex.Database.Query.order_by_desc("created_at")
    |> Laravex.Database.Query.get()
    |> Enum.map(&decode_row/1)
  end

  def unread_for(%{__struct__: mod, id: id}) do
    query_for(mod, id)
    |> Laravex.Database.Query.where_null("read_at")
    |> Laravex.Database.Query.order_by_desc("created_at")
    |> Laravex.Database.Query.get()
    |> Enum.map(&decode_row/1)
  end

  def read_for(%{__struct__: mod, id: id}) do
    query_for(mod, id)
    |> Laravex.Database.Query.where_not_null("read_at")
    |> Laravex.Database.Query.order_by_desc("created_at")
    |> Laravex.Database.Query.get()
    |> Enum.map(&decode_row/1)
  end

  def mark_as_read(%{__struct__: mod, id: id}, notification_id) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    if Laravex.Database.Schema.has_table?("notifications") do
      Laravex.Database.Connection.execute(
        """
        UPDATE notifications SET read_at = ?, updated_at = ?
        WHERE id = ? AND notifiable_type = ? AND notifiable_id = ?
        """,
        [now, now, to_string(notification_id), to_string(mod), id]
      )
    end

    :ok
  end

  def mark_as_unread(%{__struct__: mod, id: id}, notification_id) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    if Laravex.Database.Schema.has_table?("notifications") do
      Laravex.Database.Connection.execute(
        """
        UPDATE notifications SET read_at = NULL, updated_at = ?
        WHERE id = ? AND notifiable_type = ? AND notifiable_id = ?
        """,
        [now, to_string(notification_id), to_string(mod), id]
      )
    end

    :ok
  end

  def mark_all_as_read(%{__struct__: mod, id: id}) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    if Laravex.Database.Schema.has_table?("notifications") do
      Laravex.Database.Connection.execute(
        """
        UPDATE notifications SET read_at = ?, updated_at = ?
        WHERE notifiable_type = ? AND notifiable_id = ? AND read_at IS NULL
        """,
        [now, now, to_string(mod), id]
      )
    end

    :ok
  end

  defp query_for(mod, id) do
    unless Laravex.Database.Schema.has_table?("notifications") do
      raise "notifications table is missing — run migrations first"
    end

    Laravex.Database.Query.table("notifications")
    |> Laravex.Database.Query.where("notifiable_type", to_string(mod))
    |> Laravex.Database.Query.where("notifiable_id", id)
  end

  defp decode_row(row) do
    data =
      case Laravex.Support.JSON.decode(row["data"] || "{}") do
        {:ok, map} -> map
        _ -> %{}
      end

    Map.put(row, "data", data)
  end
end
