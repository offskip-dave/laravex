defmodule Laravex.Support.LazyCollection do
  @moduledoc """
  Lazy enumerable wrapper (Laravel LazyCollection lite).

      LazyCollection.make(1..1_000_000) |> LazyCollection.map(&(&1 * 2)) |> Enum.take(3)
  """

  defstruct stream: nil

  def make(enumerable) when is_list(enumerable) or is_map(enumerable) or is_struct(enumerable) do
    %__MODULE__{stream: Stream.map(enumerable, & &1)}
  end

  def make(fun) when is_function(fun, 0) do
    %__MODULE__{stream: Stream.resource(fun, fn _ -> {:halt, nil} end, fn _ -> :ok end)}
  end

  def map(%__MODULE__{stream: stream}, fun) when is_function(fun, 1) do
    %__MODULE__{stream: Stream.map(stream, fun)}
  end

  def filter(%__MODULE__{stream: stream}, fun) when is_function(fun, 1) do
    %__MODULE__{stream: Stream.filter(stream, fun)}
  end

  def reject(%__MODULE__{stream: stream}, fun) when is_function(fun, 1) do
    %__MODULE__{stream: Stream.reject(stream, fun)}
  end

  def take(%__MODULE__{stream: stream}, n) when is_integer(n) do
    %__MODULE__{stream: Stream.take(stream, n)}
  end

  def each(%__MODULE__{stream: stream}, fun) when is_function(fun, 1) do
    Stream.each(stream, fun) |> Stream.run()
    :ok
  end

  def to_list(%__MODULE__{stream: stream}), do: Enum.to_list(stream)

  def first(%__MODULE__{stream: stream}, default \\ nil) do
    case Enum.take(stream, 1) do
      [v] -> v
      _ -> default
    end
  end

  def count(%__MODULE__{stream: stream}), do: Enum.count(stream)

  defimpl Enumerable do
    def count(%{stream: stream}), do: Enumerable.count(stream)
    def member?(%{stream: stream}, value), do: Enumerable.member?(stream, value)
    def reduce(%{stream: stream}, acc, fun), do: Enumerable.reduce(stream, acc, fun)
    def slice(%{stream: stream}), do: Enumerable.slice(stream)
  end
end
