defmodule Laravex.Database.ModelNotFoundException do
  defexception [:model, :id]

  def message(%{model: model, id: id}) do
    "No query results for model [#{inspect(model)}] #{inspect(id)}"
  end
end
