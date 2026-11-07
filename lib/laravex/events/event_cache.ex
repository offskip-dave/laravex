defmodule Laravex.Events.EventCache do
  @moduledoc "Persist event → listener map to `bootstrap/cache/events.term`."

  def path(base_path \\ nil) do
    base = base_path || Laravex.Foundation.Application.base_path()
    Path.join(base, "bootstrap/cache/events.term")
  end

  def exists?(base_path \\ nil), do: File.exists?(path(base_path))

  def listen_map do
    if Code.ensure_loaded?(App.Providers.EventServiceProvider) and
         function_exported?(App.Providers.EventServiceProvider, :listen, 0) do
      App.Providers.EventServiceProvider.listen()
    else
      %{}
    end
  end

  def cache!(base_path \\ nil) do
    file = path(base_path)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, :erlang.term_to_binary(%{listen: listen_map()}))
    :ok
  end

  def load!(base_path \\ nil) do
    file = path(base_path)

    if File.exists?(file) do
      %{listen: listen} = :erlang.binary_to_term(File.read!(file))
      register(listen || %{})
      true
    else
      false
    end
  rescue
    _ -> false
  end

  def clear!(base_path \\ nil) do
    file = path(base_path)
    if File.exists?(file), do: File.rm!(file)
    :ok
  end

  def register(listen) when is_map(listen) do
    Enum.each(listen, fn {event, listeners} ->
      Enum.each(Laravex.Support.Arr.wrap(listeners), fn listener ->
        Laravex.Events.Dispatcher.listen(event, listener)
      end)
    end)

    :ok
  end
end
