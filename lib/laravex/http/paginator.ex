defmodule Laravex.Http.Paginator do
  @moduledoc "LengthAwarePaginator helpers for Blade and JSON link generation."

  def links(pager, path \\ nil) when is_map(pager) do
    page = current_page(pager)
    last = last_page(pager)
    path = path || pager_path(pager)

    prev =
      if page > 1 do
        ~s(<a href="#{page_url(pager, page - 1, path)}">&laquo; Previous</a>)
      else
        ~s(<span class="disabled">&laquo; Previous</span>)
      end

    next =
      if page < last do
        ~s(<a href="#{page_url(pager, page + 1, path)}">Next &raquo;</a>)
      else
        ~s(<span class="disabled">Next &raquo;</span>)
      end

    nums =
      elements(page, last)
      |> Enum.map(fn
        :ellipsis -> ~s(<span class="ellipsis">&hellip;</span>)
        n when n == page -> ~s(<span class="current">#{n}</span>)
        n -> ~s(<a href="#{page_url(pager, n, path)}">#{n}</a>)
      end)
      |> Enum.join(" ")

    ~s(<nav class="pagination">#{prev} #{nums} #{next}</nav>)
  end

  @doc "Build `path?…&page=n` preserving extra query params from the pager."
  def page_url(pager, page_num, path \\ nil) when is_map(pager) do
    path = path || pager_path(pager)
    query = pager_query(pager) |> Map.put("page", to_string(page_num))
    encoded = URI.encode_query(query)

    if encoded == "" do
      path
    else
      path <> "?" <> encoded
    end
  end

  @doc "Laravel-style windowed page list with `:ellipsis` atoms."
  def elements(current, last, on_each_side \\ 2) do
    last = max(1, last)
    current = min(max(1, current), last)

    if last <= on_each_side * 2 + 5 do
      Enum.to_list(1..last)
    else
      window_start = max(2, current - on_each_side)
      window_end = min(last - 1, current + on_each_side)

      middle = Enum.to_list(window_start..window_end)

      left =
        if window_start > 2 do
          [1, :ellipsis]
        else
          [1]
        end

      right =
        if window_end < last - 1 do
          [:ellipsis, last]
        else
          [last]
        end

      left ++ middle ++ right
    end
  end

  def current_page(pager),
    do: Map.get(pager, :current_page) || Map.get(pager, "current_page") || 1

  def last_page(pager),
    do: max(1, Map.get(pager, :last_page) || Map.get(pager, "last_page") || 1)

  def pager_path(pager),
    do: Map.get(pager, :path) || Map.get(pager, "path") || "/"

  def pager_query(pager) do
    (Map.get(pager, :query) || Map.get(pager, "query") || %{})
    |> Map.new(fn {k, v} -> {to_string(k), to_string(v)} end)
    |> Map.delete("page")
  end
end
