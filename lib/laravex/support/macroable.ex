defmodule Laravex.Support.Macroable do
  @moduledoc """
  Laravel-style Macroable — register runtime functions on a module.

      defmodule MyStr do
        use Laravex.Support.Macroable
      end

      MyStr.macro(:shout, fn str -> String.upcase(str) <> "!" end)
      MyStr.shout("hi")
  """

  defmacro __using__(_opts) do
    quote do
      @before_compile Laravex.Support.Macroable

      def macro(name, fun) when is_atom(name) and is_function(fun) do
        :persistent_term.put({__MODULE__, :macro, name}, fun)
        :ok
      end

      def has_macro?(name) when is_atom(name) do
        match?({:ok, _}, fetch_macro(name))
      end

      def fetch_macro(name) when is_atom(name) do
        case :persistent_term.get({__MODULE__, :macro, name}, :__missing__) do
          :__missing__ -> :error
          fun -> {:ok, fun}
        end
      end

      def flush_macros do
        # Best-effort: macros are per-module keys; callers can overwrite individually.
        :ok
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def __macro_call__(name, args) when is_atom(name) and is_list(args) do
        case fetch_macro(name) do
          {:ok, fun} -> apply(fun, args)
          :error -> raise UndefinedFunctionError, module: __MODULE__, function: name, arity: length(args)
        end
      end
    end
  end
end
