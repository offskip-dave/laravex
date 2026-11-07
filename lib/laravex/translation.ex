defmodule Laravex.Translation do
  @moduledoc "Laravel-style __() translation loader from lang/{locale}/*.exs with fallback."

  def get(key, replace \\ %{}, locale \\ nil) do
    locale = locale || Laravex.Config.Repository.get("app.locale", "en")
    fallback = Laravex.Config.Repository.get("app.fallback_locale", "en")
    {group, item} = split_key(key)

    text =
      case lookup(locale, group, item) do
        nil when locale != fallback -> lookup(fallback, group, item) || key
        nil -> key
        found -> found
      end

    Enum.reduce(replace || %{}, to_string(text), fn {k, v}, acc ->
      String.replace(acc, ":" <> to_string(k), to_string(v))
    end)
  end

  def has?(key, locale \\ nil) do
    locale = locale || Laravex.Config.Repository.get("app.locale", "en")
    {group, item} = split_key(key)
    not is_nil(lookup(locale, group, item))
  end

  defp lookup(locale, group, item) do
    map = load_group(locale, group)
    Map.get(map, item) || Map.get(map, String.to_atom(item))
  end

  defp split_key(key) do
    case String.split(to_string(key), ".", parts: 2) do
      [g, i] -> {g, i}
      [i] -> {"messages", i}
    end
  end

  defp load_group(locale, group) do
    path =
      Path.join([
        Laravex.Foundation.Application.base_path(),
        "lang",
        to_string(locale),
        "#{group}.exs"
      ])

    if File.exists?(path) do
      {val, _} = Code.eval_file(path)
      if is_map(val), do: val, else: %{}
    else
      %{}
    end
  end
end
