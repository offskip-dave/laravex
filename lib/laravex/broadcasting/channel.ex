defmodule Laravex.Broadcasting.Channel do
  @moduledoc """
  Broadcast channel authorization registry (Laravel `routes/channels.php` lite).

      Laravex.Broadcasting.Channel.channel("orders.{id}", fn user, %{"id" => id} ->
        to_string(user.id) == to_string(id)
      end)

      Laravex.Broadcasting.Channel.authorize("orders.42", user)
  """

  @table :laravex_broadcast_channels

  def ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        _ = :ets.new(@table, [:named_table, :public, :ordered_set])
        :ok
      rescue
        ArgumentError -> :ok
      end
    else
      :ok
    end
  end

  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table)
    ensure()
  end

  @doc """
  Register a channel pattern. Callback receives `(user, params_map)` and should
  return truthy to authorize.
  """
  def channel(pattern, callback)
      when (is_binary(pattern) or is_atom(pattern)) and is_function(callback, 2) do
    ensure()
    :ets.insert(@table, {to_string(pattern), callback})
    :ok
  end

  def authorize(channel_name, user) when is_binary(channel_name) do
    ensure()

    @table
    |> :ets.tab2list()
    |> Enum.find_value(false, fn {pattern, callback} ->
      case match_pattern(pattern, channel_name) do
        {:ok, params} ->
          try do
            !!callback.(user, params)
          rescue
            _ -> false
          end

        :nomatch ->
          nil
      end
    end)
  end

  def all do
    ensure()
    :ets.tab2list(@table) |> Enum.map(fn {pattern, _} -> pattern end)
  end

  defp match_pattern(pattern, name) do
    pattern_parts = String.split(pattern, ".")
    name_parts = String.split(name, ".")

    if length(pattern_parts) != length(name_parts) do
      :nomatch
    else
      Enum.zip(pattern_parts, name_parts)
      |> Enum.reduce_while(%{}, fn {pat, val}, params ->
        cond do
          String.starts_with?(pat, "{") and String.ends_with?(pat, "}") ->
            key = String.trim(pat, "{}")
            {:cont, Map.put(params, key, val)}

          pat == val ->
            {:cont, params}

          true ->
            {:halt, :nomatch}
        end
      end)
      |> case do
        :nomatch -> :nomatch
        params when is_map(params) -> {:ok, params}
      end
    end
  end
end
