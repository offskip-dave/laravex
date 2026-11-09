defmodule Laravex.Publish do
  @moduledoc "vendor:publish — copy tagged stubs from `lib/laravex/publish/` into the app."

  def publish(tag, opts \\ []) do
    force? = Keyword.get(opts, :force, false)

    base =
      case :code.priv_dir(:laravex) do
        {:error, _} -> File.cwd!()
        dir -> to_string(dir)
      end

    root = Path.join([base, "..", "lib", "laravex", "publish", tag])
    root = Path.expand(root)

    unless File.dir?(root) do
      # Fall back to source tree path
      alt = Path.join([Laravex.Foundation.Application.base_path(), "lib/laravex/publish", tag])

      if File.dir?(alt) do
        do_publish(alt, force?)
      else
        IO.puts(:stderr, "Unknown publish tag: #{tag}")
        IO.puts("Available: #{Enum.join(available_tags(), ", ")}")
      end
    else
      do_publish(root, force?)
    end
  end

  def available_tags do
    base = Path.join(Laravex.Foundation.Application.base_path(), "lib/laravex/publish")

    if File.dir?(base) do
      base |> File.ls!() |> Enum.filter(&File.dir?(Path.join(base, &1)))
    else
      []
    end
  end

  defp do_publish(root, force?) do
    root
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.each(fn src ->
      rel = Path.relative_to(src, root)
      dest = Path.join(Laravex.Foundation.Application.base_path(), rel)

      cond do
        File.exists?(dest) and not force? ->
          IO.puts("Skipped (exists): #{rel}")

        true ->
          File.mkdir_p!(Path.dirname(dest))
          File.cp!(src, dest)
          IO.puts("Published: #{rel}")
      end
    end)

    :ok
  end
end
