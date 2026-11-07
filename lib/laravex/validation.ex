defmodule Laravex.Validation do
  @moduledoc "Laravel-style validation rules with session flash helpers."

  defmodule Error do
    defexception [:errors]
    def message(%{errors: errors}), do: "The given data was invalid. " <> inspect(errors)
  end

  def validate(data, rules) when is_map(data) and is_map(rules) do
    errors =
      Enum.reduce(rules, %{}, fn {field, rule_str}, acc ->
        field = to_string(field)
        value = Map.get(data, field) || Map.get(data, String.to_atom(field))
        field_errors = check(field, value, String.split(to_string(rule_str), "|"), data)

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

  @doc """
  Validate request params. On failure, flashes `_errors` and `_old` into the session
  (picked up by ShareErrors / `@error` on the next render).
  """
  def validate_request(request, rules) do
    data = Map.merge(request.params, request.files || %{})

    case validate(data, rules) do
      {:ok, validated} ->
        {:ok, validated, request}

      {:error, errors} ->
        request =
          request
          |> Laravex.Session.Store.put("_errors", errors)
          |> Laravex.Session.Store.put("_old", request.params)
          |> then(fn r -> %{r | errors: errors, old: request.params} end)

        Process.put(:laravex_request, request)
        {:error, errors, request}
    end
  end

  defp check(field, value, rules, data) do
    Enum.flat_map(rules, fn rule ->
      case rule do
        "required" ->
          if blank?(value), do: ["The #{field} field is required."], else: []

        "string" ->
          if is_nil(value) or is_binary(value), do: [], else: ["The #{field} field must be a string."]

        "email" ->
          if is_nil(value) or (is_binary(value) and String.contains?(value, "@")),
            do: [],
            else: ["The #{field} field must be a valid email."]

        "confirmed" ->
          other = Map.get(data, field <> "_confirmation") || Map.get(data, String.to_atom(field <> "_confirmation"))
          if to_string(value || "") == to_string(other || ""), do: [], else: ["The #{field} confirmation does not match."]

        "min:" <> n ->
          min = String.to_integer(n)

          cond do
            is_binary(value) and String.length(value) < min ->
              ["The #{field} field must be at least #{min} characters."]

            is_integer(value) and value < min ->
              ["The #{field} field must be at least #{min}."]

            true ->
              []
          end

        "max:" <> n ->
          max = String.to_integer(n)

          cond do
            is_binary(value) and String.length(value) > max ->
              ["The #{field} field must not be greater than #{max} characters."]

            true ->
              []
          end

        "integer" ->
          if is_nil(value) or is_integer(value) or
               (is_binary(value) and match?({_, ""}, Integer.parse(value))),
             do: [],
             else: ["The #{field} field must be an integer."]

        "boolean" ->
          if value in [true, false, 1, 0, "1", "0", "true", "false", nil],
            do: [],
            else: ["The #{field} field must be true or false."]

        "nullable" ->
          []

        "file" ->
          case value do
            %Laravex.Http.UploadedFile{} -> []
            nil -> []
            _ -> ["The #{field} field must be a file."]
          end

        "image" ->
          case value do
            %Laravex.Http.UploadedFile{} = f ->
              if Laravex.Http.UploadedFile.image?(f),
                do: [],
                else: ["The #{field} field must be an image."]

            nil ->
              []

            _ ->
              ["The #{field} field must be an image."]
          end

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
        unless authorize(request),
          do: raise(Laravex.Http.HttpException, status: 403, message: "Forbidden")

        case Laravex.Validation.validate_request(request, rules()) do
          {:ok, _data, request} -> {:ok, request}
          {:error, errors, request} -> {:error, errors, request}
        end
      end

      defoverridable authorize: 1
    end
  end
end
