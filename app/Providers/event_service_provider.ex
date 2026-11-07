defmodule App.Providers.EventServiceProvider do
  @moduledoc """
  Register event → listener mappings (Laravel EventServiceProvider).

  Override `listen/0` in your app, or append via `make:event` / `make:listener`.
  When `bootstrap/cache/events.term` exists (`event:cache`), that map is loaded instead.
  """

  def register, do: :ok

  def boot do
    if Laravex.Events.EventCache.exists?() do
      Laravex.Events.EventCache.load!()
    else
      Laravex.Events.EventCache.register(listen())
    end

    :ok
  end

  @doc "Map of event module => listener module(s)."
  def listen do
    %{}
  end
end
