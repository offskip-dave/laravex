defmodule Laravex.Console.Schedule do
  @moduledoc """
  Task scheduling registry (`schedule:run`) with cron-style expressions.

  Options on `call/3`:
  - `without_overlapping: true` — skip if a previous run of the same task is still marked running
  - `name:` — stable mutex key (defaults to a hash of the expression)
  """

  @table :laravex_schedule

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

  def reset do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table)
    ensure()
  end

  def call(expression, fun, opts \\ []) when is_binary(expression) and is_function(fun, 0) do
    ensure()
    :ets.insert(@table, {:task, %{expression: expression, fun: fun, opts: opts}})
    :ok
  end

  def command(name, expression, opts \\ []) do
    call(expression, fn -> Laravex.Console.Router.dispatch(name) end, opts)
  end

  def run(now \\ :calendar.universal_time()) do
    ensure()

    :ets.lookup(@table, :task)
    |> Enum.each(fn
      {:task, %{expression: expr, fun: fun, opts: opts}} ->
        if due?(expr, now), do: run_task(fun, opts || [])

      {:task, %{expression: expr, fun: fun}} ->
        if due?(expr, now), do: run_task(fun, [])

      _ ->
        :ok
    end)

    :ok
  end

  def all do
    ensure()
    :ets.lookup(@table, :task) |> Enum.map(fn {:task, t} -> t end)
  end

  def due?(expression, now \\ :calendar.universal_time()) do
    {{y, mo, d}, {h, mi, _s}} = now
    dow = :calendar.day_of_the_week({y, mo, d})

    case expression do
      "everyMinute" ->
        mark_and_check({:everyMinute, y, mo, d, h, mi})

      "hourly" ->
        mi == 0 and mark_and_check({:hourly, y, mo, d, h})

      "daily" ->
        h == 0 and mi == 0 and mark_and_check({:daily, y, mo, d})

      "weekly" ->
        dow == 1 and h == 0 and mi == 0 and mark_and_check({:weekly, y, mo, d})

      cron when is_binary(cron) ->
        match_cron(cron, %{minute: mi, hour: h, day: d, month: mo, dow: dow})

      _ ->
        false
    end
  end

  defp run_task(fun, opts) do
    if Keyword.get(opts, :without_overlapping, false) do
      key = mutex_key(opts)
      expires = Keyword.get(opts, :expires_at, 3600)

      if acquire_mutex(key, expires) do
        try do
          fun.()
        after
          release_mutex(key)
        end
      else
        :skipped
      end
    else
      fun.()
    end
  end

  defp mutex_key(opts) do
    name = Keyword.get(opts, :name) || Keyword.get(opts, :mutex) || "schedule-task"
    "schedule:overlap:" <> to_string(name)
  end

  defp acquire_mutex(key, expires) do
    case Laravex.Cache.Manager.get(key) do
      nil ->
        Laravex.Cache.Manager.put(key, true, expires)
        true

      _ ->
        false
    end
  end

  defp release_mutex(key), do: Laravex.Cache.Manager.forget(key)

  defp mark_and_check(key) do
    ensure()
    ran_key = {:ran, key}

    case :ets.lookup(@table, ran_key) do
      [_] ->
        false

      [] ->
        :ets.insert(@table, {ran_key, true})
        true
    end
  end

  defp match_cron(expr, now) do
    parts = String.split(expr, " ", trim: true)

    case parts do
      [minute, hour, day, month, dow] ->
        field_match?(minute, now.minute) and
          field_match?(hour, now.hour) and
          field_match?(day, now.day) and
          field_match?(month, now.month) and
          field_match?(dow, rem(now.dow, 7))

      _ ->
        false
    end
  end

  defp field_match?("*", _), do: true

  defp field_match?("*/" <> step, value) do
    case Integer.parse(step) do
      {n, ""} when n > 0 -> rem(value, n) == 0
      _ -> false
    end
  end

  defp field_match?(field, value) do
    field
    |> String.split(",")
    |> Enum.any?(fn part ->
      cond do
        String.contains?(part, "-") ->
          [a, b] = String.split(part, "-", parts: 2)
          value >= String.to_integer(a) and value <= String.to_integer(b)

        true ->
          case Integer.parse(part) do
            {n, ""} -> n == value
            _ -> false
          end
      end
    end)
  end
end
