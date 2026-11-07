defmodule Laravex.Translation do
  @moduledoc "Simple __() translation loader from lang/{locale}/*.exs"

  def get(key, replace \\ %{}, locale \\ nil) do
    locale = locale || Laravex.Config.Repository.get("app.locale", "en")
    {group, item} = split_key(key)
    map = load_group(locale, group)
    text = Map.get(map, item, key)

    Enum.reduce(replace, text, fn {k, v}, acc ->
      String.replace(acc, ":" <> to_string(k), to_string(v))
    end)
  end

  defp split_key(key) do
    case String.split(key, ".", parts: 2) do
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
      val
    else
      %{}
    end
  end
end
