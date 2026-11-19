defmodule Laravex.Validation.Rule do
  @moduledoc """
  Custom validation rule behaviour and fluent database rules (Laravel `Rule`).

      defmodule App.Rules.Uppercase do
        @behaviour Laravex.Validation.Rule
        def passes?(_attr, value), do: is_binary(value) and value == String.upcase(value)
        def message, do: "must be uppercase"
      end

      %{"email" => ["required", Rule.unique("users", "email") |> Rule.where("active", 1)]}
  """

  @callback passes?(attribute :: String.t(), value :: term()) :: boolean()
  @callback message() :: String.t()
  @optional_callbacks message: 0

  def unique(table, column \\ nil) do
    %Laravex.Validation.Rule.Database{
      type: :unique,
      table: to_string(table),
      column: column && to_string(column),
      wheres: []
    }
  end

  def exists(table, column \\ nil) do
    %Laravex.Validation.Rule.Database{
      type: :exists,
      table: to_string(table),
      column: column && to_string(column),
      wheres: []
    }
  end

  def where(%Laravex.Validation.Rule.Database{} = rule, column, value) do
    %{rule | wheres: rule.wheres ++ [{to_string(column), value}]}
  end

  def where_not_null(%Laravex.Validation.Rule.Database{} = rule, column) do
    %{rule | wheres: rule.wheres ++ [{:not_null, to_string(column)}]}
  end

  def ignore(%Laravex.Validation.Rule.Database{} = rule, id, id_column \\ "id") do
    %{rule | ignore_id: id, ignore_column: to_string(id_column)}
  end
end
