defmodule App.Http.Controllers.Controller do
  @moduledoc "Port of app/Http/Controllers/Controller.php"

  defmacro __using__(_opts) do
    quote do
      import Laravex.Support.Helpers
    end
  end
end
