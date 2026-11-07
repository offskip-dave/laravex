defmodule Laravex.Eloquex.Factory do
  @moduledoc """
  Eloquex model factory base.

      defmodule Database.Factories.PostFactory do
        use Laravex.Eloquex.Factory, model: App.Models.Post

        def definition do
          %{"title" => "Hello"}
        end

        defstate :draft do
          %{"published" => false}
        end
      end
  """

  defmacro __using__(opts) do
    model = Keyword.fetch!(opts, :model)

    quote do
      @eloquex_model unquote(model)
      Module.register_attribute(__MODULE__, :eloquex_states, accumulate: true)
      import Laravex.Eloquex.Factory, only: [defstate: 2]
      @before_compile Laravex.Eloquex.Factory

      def model, do: @eloquex_model

      def definition, do: %{}

      def make(attrs \\ %{}) do
        mod = model()

        definition()
        |> Map.merge(stringify(attrs))
        |> then(fn attrs -> mod.new(attrs) end)
      end

      def create(attrs \\ %{}) do
        mod = model()

        definition()
        |> Map.merge(stringify(attrs))
        |> then(fn attrs -> mod.create(attrs) end)
      end

      def make_state(name, attrs \\ %{}) do
        make(Map.merge(state(name), stringify(attrs)))
      end

      def create_state(name, attrs \\ %{}) do
        create(Map.merge(state(name), stringify(attrs)))
      end

      defoverridable definition: 0, make: 0, make: 1, create: 0, create: 1

      defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
    end
  end

  defmacro __before_compile__(env) do
    states = Module.get_attribute(env.module, :eloquex_states) || []

    state_clauses =
      Enum.map(states, fn {name, body} ->
        quote do
          def state(unquote(name)), do: unquote(body)
        end
      end)

    quote do
      unquote_splicing(state_clauses)
      def state(_), do: %{}
    end
  end

  @doc """
  Register a named factory state.

      defstate :unverified do
        %{"email_verified_at" => nil}
      end
  """
  defmacro defstate(name, do: body) do
    quote do
      @eloquex_states {unquote(name), unquote(Macro.escape(body))}
    end
  end
end
