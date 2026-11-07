defmodule Laravex.Http.Paginator do
  @moduledoc "Simple LengthAwarePaginator helpers for Blade."

  def links(pager, path \\ nil) when is_map(pager) do
    page = Map.get(pager, :current_page) || Map.get(pager, "current_page") || 1
    last = Map.get(pager, :last_page) || Map.get(pager, "last_page") || 1
    path = path || Map.get(pager, :path) || Map.get(pager, "path") || "/"
    last = max(1, last)

    prev =
      if page > 1 do
        ~s(<a href="#{path}?page=#{page - 1}">&laquo; Previous</a>)
      else
        ~s(<span class="disabled">&laquo; Previous</span>)
      end

    next =
      if page < last do
        ~s(<a href="#{path}?page=#{page + 1}">Next &raquo;</a>)
      else
        ~s(<span class="disabled">Next &raquo;</span>)
      end

    nums =
      for n <- 1..last do
        if n == page do
          ~s(<span class="current">#{n}</span>)
        else
          ~s(<a href="#{path}?page=#{n}">#{n}</a>)
        end
      end
      |> Enum.join(" ")

    ~s(<nav class="pagination">#{prev} #{nums} #{next}</nav>)
  end
end
