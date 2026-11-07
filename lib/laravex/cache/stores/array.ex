defmodule Laravex.Cache.Stores.Array do
  @moduledoc false
  @behaviour Laravex.Cache.Store

  @impl true
  def get(key, %{array: array}), do: Map.get(array, key)

  @impl true
  def put(_key, _entry, _state), do: :ok

  @impl true
  def forget(_key), do: :ok

  @impl true
  def flush, do: :ok
end
