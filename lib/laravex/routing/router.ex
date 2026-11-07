defmodule Laravex.Routing.Router do
  @moduledoc """
  Laravel-style router: verbs, `{param}` paths, names, groups, resources.
  """

  @table :laravex_routes
  @meta :laravex_route_meta

  def reset do
    for t <- [@table, @meta] do
      if :ets.whereis(t) != :undefined, do: :ets.delete(t)
    end

    :ets.new(@table, [:named_table, :public, :ordered_set, read_concurrency: true])
    :ets.new(@meta, [:named_table, :public, :set, read_concurrency: true])
    :ets.insert(@meta, {:group_stack, []})
    :ets.insert(@meta, {:named, %{}})
    :ok
  end

  def get(path, handler, opts \\ []), do: add("GET", path, handler, opts)
  def post(path, handler, opts \\ []), do: add("POST", path, handler, opts)
  def put(path, handler, opts \\ []), do: add("PUT", path, handler, opts)
  def patch(path, handler, opts \\ []), do: add("PATCH", path, handler, opts)
  def delete(path, handler, opts \\ []), do: add("DELETE", path, handler, opts)
  def any(path, handler, opts \\ []) do
    Enum.each(~w(GET POST PUT PATCH DELETE), &add(&1, path, handler, opts))
  end

  def group(opts, fun) when is_function(fun, 0) do
    ensure()
    [{:group_stack, stack}] = :ets.lookup(@meta, :group_stack)
    :ets.insert(@meta, {:group_stack, [opts | stack]})
    fun.()
    :ets.insert(@meta, {:group_stack, stack})
    :ok
  end

  def resource(name, controller, opts \\ []) do
    only = Keyword.get(opts, :only, [:index, :create, :store, :show, :edit, :update, :destroy])
    base = "/" <> String.trim(name, "/")

    if :index in only, do: get(base, &controller_call(controller, :index, &1), name: "#{name}.index")
    if :create in only, do: get(base <> "/create", &controller_call(controller, :create, &1), name: "#{name}.create")
    if :store in only, do: post(base, &controller_call(controller, :store, &1), name: "#{name}.store")
    if :show in only, do: get(base <> "/{id}", &controller_call(controller, :show, &1), name: "#{name}.show")
    if :edit in only, do: get(base <> "/{id}/edit", &controller_call(controller, :edit, &1), name: "#{name}.edit")
    if :update in only, do: put(base <> "/{id}", &controller_call(controller, :update, &1), name: "#{name}.update")
    if :destroy in only, do: delete(base <> "/{id}", &controller_call(controller, :destroy, &1), name: "#{name}.destroy")
    :ok
  end

  def dispatch(%Laravex.Http.Request{method: method, path: path} = request) do
    ensure()
    path = normalize(path)

    :ets.tab2list(@table)
    |> Enum.find_value(fn
      {{^method, pattern}, handler, opts} ->
        case match_path(pattern, path) do
          {:ok, route_params} ->
            request = %{request | route_params: route_params, params: Map.merge(request.params, route_params)}
            {:ok, invoke(handler, request, opts)}

          :error ->
            nil
        end

      _ ->
        nil
    end)
    |> case do
      nil -> :error
      other -> other
    end
  end

  def url(name, params \\ %{}) do
    ensure()
    [{:named, named}] = :ets.lookup(@meta, :named)

    case Map.get(named, to_string(name)) do
      nil -> raise "Route [#{name}] not defined."
      pattern -> fill_pattern(pattern, params)
    end
  end

  def routes do
    ensure()

    :ets.tab2list(@table)
    |> Enum.map(fn {{method, pattern}, _handler, opts} ->
      %{method: method, uri: pattern, name: Keyword.get(opts, :name), middleware: Keyword.get(opts, :middleware, [])}
    end)
  end

  defp add(method, path, handler, opts) do
    ensure()
    [{:group_stack, stack}] = :ets.lookup(@meta, :group_stack)
    group_opts = Enum.reduce(Enum.reverse(stack), [], fn g, acc -> Keyword.merge(acc, Enum.to_list(g)) end)
    opts = Keyword.merge(group_opts, opts)
    prefix = Keyword.get(opts, :prefix, "")
    full = normalize(Path.join(["/", prefix, path]) |> String.replace("//", "/"))

    :ets.insert(@table, {{method, full}, handler, opts})

    if name = Keyword.get(opts, :name) do
      [{:named, named}] = :ets.lookup(@meta, :named)
      :ets.insert(@meta, {:named, Map.put(named, to_string(name), full)})
    end

    :ok
  end

  defp invoke(handler, request, _opts) when is_function(handler, 1), do: handler.(request)

  defp invoke({mod, fun}, request, _opts) when is_atom(mod) and is_atom(fun) do
    apply(mod, fun, [request])
  end

  defp controller_call(controller, action, request) do
    apply(controller, action, [request])
  end

  defp match_path(pattern, path) do
    pattern_parts = String.split(pattern, "/", trim: true)
    path_parts = String.split(path, "/", trim: true)

    if length(pattern_parts) != length(path_parts) do
      :error
    else
      Enum.zip(pattern_parts, path_parts)
      |> Enum.reduce_while({:ok, %{}}, fn {pp, vp}, {:ok, acc} ->
        cond do
          String.starts_with?(pp, "{") and String.ends_with?(pp, "}") ->
            key = String.slice(pp, 1..-2//1)
            {:cont, {:ok, Map.put(acc, key, vp)}}

          pp == vp ->
            {:cont, {:ok, acc}}

          true ->
            {:halt, :error}
        end
      end)
    end
  end

  defp fill_pattern(pattern, params) do
    Enum.reduce(Map.new(params, fn {k, v} -> {to_string(k), to_string(v)} end), pattern, fn {k, v}, acc ->
      String.replace(acc, "{#{k}}", v)
    end)
  end

  defp normalize("/"), do: "/"

  defp normalize(path) do
    path = "/" <> String.trim(path, "/")
    if path == "/", do: "/", else: String.trim_trailing(path, "/")
  end

  defp ensure do
    if :ets.whereis(@table) == :undefined, do: reset()
    :ok
  end
end
