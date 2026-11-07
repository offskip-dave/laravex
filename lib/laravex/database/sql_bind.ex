defmodule Laravex.Database.SqlBind do
  @moduledoc false

  def bind(sql, bindings) do
    Enum.reduce(bindings, sql, fn val, acc ->
      String.replace(acc, "?", quote_val(val), global: false)
    end)
  end

  def quote_val(nil), do: "NULL"
  def quote_val(true), do: "1"
  def quote_val(false), do: "0"
  def quote_val(%DateTime{} = v), do: quote_val(DateTime.to_iso8601(v))
  def quote_val(v) when is_integer(v) or is_float(v), do: to_string(v)

  def quote_val(v) do
    "'" <> String.replace(to_string(v), "'", "''") <> "'"
  end
end
