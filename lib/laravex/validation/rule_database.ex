defmodule Laravex.Validation.Rule.Database do
  @moduledoc false

  defstruct type: :unique,
            table: nil,
            column: nil,
            wheres: [],
            ignore_id: nil,
            ignore_column: "id"

  def validate(_field, nil, _), do: []
  def validate(_field, "", _), do: []

  def validate(field, value, %__MODULE__{} = rule) do
    column = rule.column || to_string(field)

    q =
      Laravex.Database.Query.table(rule.table)
      |> Laravex.Database.Query.where(column, value)
      |> apply_wheres(rule.wheres)

    q =
      if rule.ignore_id do
        Laravex.Database.Query.where(q, rule.ignore_column || "id", "!=", rule.ignore_id)
      else
        q
      end

    case rule.type do
      :unique ->
        if Laravex.Database.Query.exists?(q),
          do: ["The #{field} has already been taken."],
          else: []

      :exists ->
        if Laravex.Database.Query.exists?(q),
          do: [],
          else: ["The selected #{field} is invalid."]
    end
  rescue
    _ ->
      case rule.type do
        :unique -> []
        :exists -> ["The selected #{field} is invalid."]
      end
  end

  defp apply_wheres(q, wheres) do
    Enum.reduce(wheres, q, fn
      {:not_null, col}, acc -> Laravex.Database.Query.where_not_null(acc, col)
      {col, val}, acc -> Laravex.Database.Query.where(acc, col, val)
    end)
  end
end
