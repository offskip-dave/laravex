defmodule Laravex.Eloquex.Factory do
  @moduledoc """
  Eloquex model factory base.

      defmodule Database.Factories.PostFactory do
        use Laravex.Eloquex.Factory, model: App.Models.Post

        def definition do
          %{"title" => "Hello"}
        end
      end
  """

  defmacro __using__(opts) do
    model = Keyword.fetch!(opts, :model)

    quote do
      @eloquex_model unquote(model)
      Module.register_attribute(__MODULE__, :eloquex_states, accumulate: true)

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

      def state(name) when is_atom(name) do
        case Keyword.get(states(), name) do
          nil -> %{}
          fun when is_function(fun, 0) -> fun.()
          map when is_map(map) -> map
        end
      end

      def make_state(name, attrs \\ %{}) do
        make(Map.merge(state(name), stringify(attrs)))
      end

      def create_state(name, attrs \\ %{}) do
        create(Map.merge(state(name), stringify(attrs)))
      end

      def states, do: []

      defoverridable definition: 0, states: 0, make: 0, make: 1, create: 0, create: 1

      defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
    end
  end
end
