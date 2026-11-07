defmodule Laravex.Validation do
  @moduledoc "Laravel-style validation rules."

  defmodule Error do
    defexception [:errors]
    def message(%{errors: errors}), do: "The given data was invalid. " <> inspect(errors)
  end

  def validate(data, rules) when is_map(data) and is_map(rules) do
    errors =
      Enum.reduce(rules, %{}, fn {field, rule_str}, acc ->
        field = to_string(field)
        value = Map.get(data, field) || Map.get(data, String.to_atom(field))
        field_errors = check(field, value, String.split(to_string(rule_str), "|"))

        if field_errors == [] do
          acc
        else
          Map.put(acc, field, field_errors)
        end
      end)

    if map_size(errors) == 0 do
      {:ok, data}
    else
      {:error, errors}
    end
  end

  def validate!(data, rules) do
    case validate(data, rules) do
      {:ok, data} -> data
      {:error, errors} -> raise Error, errors: errors
    end
  end

  defp check(_field, value, rules) do
    Enum.flat_map(rules, fn rule ->
      case rule do
        "required" ->
          if blank?(value), do: ["The field is required."], else: []

        "string" ->
          if is_nil(value) or is_binary(value), do: [], else: ["The field must be a string."]

        "email" ->
          if is_nil(value) or (is_binary(value) and String.contains?(value, "@")),
            do: [],
            else: ["The field must be a valid email."]

        "confirmed" ->
          []

        "min:" <> n ->
          min = String.to_integer(n)

          cond do
            is_binary(value) and String.length(value) < min ->
              ["The field must be at least #{min} characters."]

            is_integer(value) and value < min ->
              ["The field must be at least #{min}."]

            true ->
              []
          end

        "max:" <> n ->
          max = String.to_integer(n)

          cond do
            is_binary(value) and String.length(value) > max ->
              ["The field must not be greater than #{max} characters."]

            true ->
              []
          end

        "integer" ->
          if is_nil(value) or is_integer(value) or (is_binary(value) and match?({_, ""}, Integer.parse(value))),
            do: [],
            else: ["The field must be an integer."]

        "boolean" ->
          if value in [true, false, 1, 0, "1", "0", "true", "false", nil],
            do: [],
            else: ["The field must be true or false."]

        "nullable" ->
          []

        _ ->
          []
      end
    end)
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end

defmodule Laravex.Http.FormRequest do
  @moduledoc "Base form request behaviour."

  @callback rules() :: map()
  @callback authorize(request :: map()) :: boolean()

  defmacro __using__(_opts) do
    quote do
      @behaviour Laravex.Http.FormRequest

      def authorize(_request), do: true

      def validate_request(request) do
        unless authorize(request), do: raise(Laravex.Http.HttpException, status: 403, message: "Forbidden")

        case Laravex.Validation.validate(request.params, rules()) do
          {:ok, _} -> {:ok, request}
          {:error, errors} -> {:error, errors}
        end
      end

      defoverridable authorize: 1
    end
  end
end
