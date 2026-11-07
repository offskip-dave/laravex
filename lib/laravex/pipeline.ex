defmodule Laravex.Pipeline do
  @moduledoc """
  Laravel-style passable pipeline (Illuminate `Pipeline`).

      Laravex.Pipeline.send(passable)
      |> Laravex.Pipeline.through([fn x -> x end, {MyPipe, :handle}, MyPipe])
      |> Laravex.Pipeline.via(:process)
      |> Laravex.Pipeline.then(fn result -> result end)

  Return `{:halt, value}` from a pipe to stop early; `then/2` still receives the halted value.
  """

  defstruct passable: nil, pipes: [], method: :handle

  def send(passable), do: %__MODULE__{passable: passable}

  def through(%__MODULE__{} = pipeline, pipes) when is_list(pipes) do
    %{pipeline | pipes: pipeline.pipes ++ List.wrap(pipes)}
  end

  def via(%__MODULE__{} = pipeline, method) when is_atom(method) do
    %{pipeline | method: method}
  end

  def then(%__MODULE__{passable: passable, pipes: pipes, method: method}, destination)
      when is_function(destination, 1) do
    result =
      Enum.reduce_while(pipes, passable, fn pipe, carried ->
        case carry(pipe, carried, method) do
          {:halt, value} -> {:halt, value}
          other -> {:cont, other}
        end
      end)

    destination.(result)
  end

  defp carry(fun, passable, _method) when is_function(fun, 1), do: fun.(passable)

  defp carry(fun, passable, _method) when is_function(fun, 0) do
    case fun.() do
      {:halt, _} = halt -> halt
      other -> other || passable
    end
  end

  defp carry({mod, fun}, passable, _method)
       when is_atom(mod) and is_atom(fun),
       do: apply(mod, fun, [passable])

  defp carry(mod, passable, method) when is_atom(mod), do: apply(mod, method, [passable])

  defp carry(other, _passable, _method) do
    raise ArgumentError,
          "Laravex.Pipeline expected a function, module, or {module, fun}, got: #{inspect(other)}"
  end
end
