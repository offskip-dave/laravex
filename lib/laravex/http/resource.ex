defmodule Laravex.Http.Resource do
  @moduledoc """
  Laravel-style JSON API resource.

      defmodule App.Http.Resources.UserResource do
        use Laravex.Http.Resource

        def to_map(user) do
          %{id: user.id, name: user.name, email: user.email}
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      def collection(models) when is_list(models), do: Enum.map(models, &to_map/1)

      def make(model) do
        Laravex.Http.Response.json(%{data: to_map(model)})
      end

      def collection_response(models) when is_list(models) do
        Laravex.Http.Response.json(%{data: collection(models)})
      end

      def paginated(page) when is_map(page) do
        Laravex.Http.Response.json_paginated(page, &to_map/1)
      end
    end
  end
end
