defmodule Laravex.Foundation.Server do
  @moduledoc false
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    base_path = Keyword.get(opts, :base_path, File.cwd!())
    app = Bootstrap.App.build(base_path) |> Laravex.Foundation.Application.create()
    {:ok, %{app: app, base_path: base_path}}
  end

  def boot!(base_path \\ File.cwd!()) do
    Bootstrap.App.build(base_path) |> Laravex.Foundation.Application.create()
  end
end
