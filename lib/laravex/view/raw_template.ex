defmodule Laravex.View.RawTemplate do
  @moduledoc """
  Inline Blade template returned from a class component `render/1`
  (Laravel `Illuminate\\View\\RawTemplate`, #62419).

      def render(assigns) do
        %Laravex.View.RawTemplate{template: \"<div>{{ message }}</div>\"}
      end
  """

  defstruct [:template]

  def new(template) when is_binary(template), do: %__MODULE__{template: template}

  def render(%__MODULE__{template: template}, assigns) when is_map(assigns) do
    Laravex.View.render_string(template, assigns)
  end
end
