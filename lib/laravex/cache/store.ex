defmodule Laravex.Cache.Store do
  @moduledoc """
  Cache persistence driver (Phase C1).

  The public API remains `Laravex.Cache.Manager`; GenServer state holds the
  in-memory `array` layer while store modules handle file/database backing.
  """

  @type entry :: %{value: term(), expires: integer() | nil}

  @callback get(key :: String.t(), state :: map()) :: entry() | nil
  @callback put(key :: String.t(), entry :: entry(), state :: map()) :: :ok
  @callback forget(key :: String.t()) :: :ok
  @callback flush() :: :ok
end

defmodule Laravex.Cache.Resolver do
  @moduledoc false

  @supported ~w(array file database redis)

  def module(driver) when is_binary(driver) do
    unless driver in @supported do
      raise ArgumentError,
            "Cache store uses unsupported driver #{inspect(driver)}. " <>
              "Supported: #{Enum.join(@supported, ", ")}."
    end

    case driver do
      "array" -> Laravex.Cache.Stores.Array
      "file" -> Laravex.Cache.Stores.File
      "database" -> Laravex.Cache.Stores.Database
      "redis" -> Laravex.Cache.Stores.Redis
    end
  end

  def effective do
    name = to_string(Laravex.Config.Repository.get("cache.default", "array"))
    stores = Laravex.Config.Repository.get("cache.stores", %{})
    cfg = Map.get(stores, name) || Map.get(stores, String.to_atom(name)) || %{}
    driver = to_string(Map.get(cfg, "driver") || Map.get(cfg, :driver) || name)

    if driver == "database" and not safe_has_cache_table?() do
      "array"
    else
      driver
    end
    |> module()
  end

  defp safe_has_cache_table? do
    Laravex.Database.Schema.has_table?("cache")
  rescue
    _ -> false
  end
end
