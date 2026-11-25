defmodule Laravex.JsonSchema do
  @moduledoc """
  Thin JSON Schema → Laravex validation rules port (Laravel `JsonSchema::rules`, #62355).

  Supports a subset of object schemas:

      JsonSchema.rules(%{
        "type" => "object",
        "required" => ["email"],
        "properties" => %{
          "email" => %{"type" => "string", "format" => "email", "maxLength" => 254},
          "age" => %{"type" => "integer", "minimum" => 0}
        }
      })
  """

  @max_nodes 20_000

  def rules(schema) when is_map(schema) do
    {result, _nodes} = properties(schema, nil, 0)
    result
  end

  defp properties(schema, prefix, nodes) do
    required = Map.get(schema, "required", []) |> Enum.map(&to_string/1) |> MapSet.new()
    props = Map.get(schema, "properties", %{})

    Enum.reduce(props, {%{}, nodes}, fn {name, property}, {acc, n} ->
      attr =
        if prefix do
          "#{prefix}.#{escape_dot(name)}"
        else
          escape_dot(name)
        end

      {field_rules, nested, n2} =
        one_property(property, attr, MapSet.member?(required, to_string(name)), not is_nil(prefix), n)

      {Map.merge(Map.put(acc, attr, field_rules), nested), n2}
    end)
  end

  defp one_property(schema, attr, required?, nested?, nodes) when is_map(schema) do
    nodes = nodes + 1
    if nodes > @max_nodes, do: raise(ArgumentError, "JSON Schema expands beyond #{@max_nodes} nodes")

    presence = presence_rules(schema, required?, nested?)
    types = types_of(schema)
    type = List.first(types)

    type_rules = type_rules(type, schema)
    {nested, nodes} = nested_rules(type, schema, attr, nodes)

    {presence ++ type_rules, nested, nodes}
  end

  defp one_property(_, _attr, required?, nested?, nodes) do
    {presence_rules(%{}, required?, nested?), %{}, nodes + 1}
  end

  defp presence_rules(schema, required?, nested?) do
    nullable? = nullable?(schema)

    cond do
      required? and not nested? and nullable? -> ["present", "nullable"]
      required? and not nested? -> ["required"]
      nullable? -> ["sometimes", "nullable"]
      required? -> ["sometimes", "filled"]
      true -> ["sometimes"]
    end
  end

  defp nested_rules("object", schema, attr, nodes) do
    properties(schema, attr, nodes)
  end

  defp nested_rules("array", schema, attr, nodes) do
    case Map.get(schema, "items") do
      %{} = items ->
        {item_rules, nested, n} = one_property(items, "#{attr}.*", false, true, nodes)
        {Map.put(nested, "#{attr}.*", item_rules), n}

      _ ->
        {%{}, nodes}
    end
  end

  defp nested_rules(_, _, _, nodes), do: {%{}, nodes}

  defp type_rules("string", schema) do
    ["string"]
    |> maybe_add(Map.get(schema, "format") == "email", fn -> "email" end)
    |> maybe_add(Map.get(schema, "format") == "uri", fn -> "url" end)
    |> maybe_add(is_integer(Map.get(schema, "minLength")), fn -> "min:#{Map.get(schema, "minLength")}" end)
    |> maybe_add(is_integer(Map.get(schema, "maxLength")), fn -> "max:#{Map.get(schema, "maxLength")}" end)
  end

  defp type_rules("integer", schema) do
    min = Map.get(schema, "minimum")
    max = Map.get(schema, "maximum")

    ["integer"]
    |> maybe_add(is_number(min), fn -> "min:#{trunc(min)}" end)
    |> maybe_add(is_number(max), fn -> "max:#{trunc(max)}" end)
  end

  defp type_rules("number", schema) do
    min = Map.get(schema, "minimum")
    max = Map.get(schema, "maximum")

    ["numeric"]
    |> maybe_add(is_number(min), fn -> "min:#{min}" end)
    |> maybe_add(is_number(max), fn -> "max:#{max}" end)
  end

  defp type_rules("boolean", _), do: ["boolean"]

  defp type_rules("array", schema) do
    ["array"]
    |> maybe_add(Map.get(schema, "uniqueItems") == true, fn -> "distinct" end)
  end

  defp type_rules("object", schema) do
    keys = schema |> Map.get("properties", %{}) |> Map.keys() |> Enum.map(&to_string/1)

    if keys == [] do
      ["array"]
    else
      ["array", "required_array_keys:" <> Enum.join(keys, ",")]
    end
  end

  defp type_rules(_, _), do: []

  defp maybe_add(rules, true, rule) when is_function(rule, 0), do: rules ++ [rule.()]
  defp maybe_add(rules, true, rule), do: rules ++ [rule]
  defp maybe_add(rules, false, _), do: rules

  defp types_of(schema) do
    case Map.get(schema, "type") do
      list when is_list(list) -> Enum.map(list, &to_string/1)
      nil -> []
      t -> [to_string(t)]
    end
  end

  defp nullable?(schema) do
    "null" in types_of(schema) or Map.get(schema, "nullable") == true
  end

  defp escape_dot(name), do: name |> to_string() |> String.replace(".", "\\.")
end
