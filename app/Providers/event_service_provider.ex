defmodule App.Providers.EventServiceProvider do
  @moduledoc """
  Register event → listener mappings (Laravel EventServiceProvider).

  Override `listen/0` in your app, or append via `make:event` / `make:listener`.
  """

  def register, do: :ok

  def boot do
    Enum.each(listen(), fn {event, listeners} ->
      Enum.each(List.wrap(listeners), fn listener ->
        Laravex.Events.Dispatcher.listen(event, listener)
      end)
    end)

    :ok
  end

  @doc "Map of event module => listener module(s)."
  def listen do
    %{}
  end
end
