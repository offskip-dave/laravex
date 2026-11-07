defmodule Laravex.Validation do
  @moduledoc "Laravel-style validation rules with session flash helpers."

  defmodule Error do
    defexception [:errors]
    def message(%{errors: errors}), do: "The given data was invalid. " <> inspect(errors)
  end

  defmodule Failed do
    @moduledoc "Raised to redirect back with errors (web) or return 422 (JSON)."
    defexception [:errors, :request]

    def message(_), do: "The given data was invalid."
  end

  def validate(data, rules) when is_map(data) and is_map(rules) do
    errors =
      Enum.reduce(rules, %{}, fn {field, rule_spec}, acc ->
        field = to_string(field)
        value = Map.get(data, field) || Map.get(data, String.to_atom(field))
        field_errors = check(field, value, normalize_rules(rule_spec), data)

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
  Validate request params. On failure, flashes `_errors` and `_old`.
  For non-JSON requests, raises `Failed` so the kernel can redirect back.
  """
  def validate_request(request, rules) do
    data = Map.merge(request.params, request.files || %{})

    case validate(data, rules) do
      {:ok, validated} ->
        {:ok, validated, request}

      {:error, errors} ->
        request = flash_errors(request, errors)
        Process.put(:laravex_request, request)

        if Laravex.Http.Request.expects_json?(request) do
          {:error, errors, request}
        else
          raise Failed, errors: errors, request: request
        end
    end
  end

  def flash_errors(request, errors) do
    request
    |> Laravex.Session.Store.put("_errors", errors)
    |> Laravex.Session.Store.put("_old", request.params)
    |> then(fn r -> %{r | errors: errors, old: request.params} end)
  end

  defp normalize_rules(rules) when is_binary(rules), do: String.split(rules, "|", trim: true)
  defp normalize_rules(rules) when is_list(rules), do: rules
  defp normalize_rules(rule) when is_atom(rule), do: [rule]
  defp normalize_rules(other), do: [other]

  defp check(field, value, rules, data) do
    Enum.flat_map(rules, fn rule ->
      case rule do
        mod when is_atom(mod) and mod not in [nil, true, false] ->
          run_rule_module(field, value, data, mod)

        "required" ->
          if blank?(value), do: ["The #{field} field is required."], else: []

        "string" ->
          if is_nil(value) or is_binary(value), do: [], else: ["The #{field} field must be a string."]

        "email" ->
          if is_nil(value) or (is_binary(value) and String.contains?(value, "@")),
            do: [],
            else: ["The #{field} field must be a valid email."]

        "confirmed" ->
          other =
            Map.get(data, field <> "_confirmation") ||
              Map.get(data, String.to_atom(field <> "_confirmation"))

          if to_string(value || "") == to_string(other || ""),
            do: [],
            else: ["The #{field} confirmation does not match."]

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

        "in:" <> list ->
          allowed = String.split(list, ",")

          if is_nil(value) or to_string(value) in allowed,
            do: [],
            else: ["The selected #{field} is invalid."]

        "regex:" <> pattern ->
          {:ok, re} = Regex.compile(pattern)

          if is_nil(value) or (is_binary(value) and Regex.match?(re, value)),
            do: [],
            else: ["The #{field} format is invalid."]

        "unique:" <> rest ->
          unique_error(field, value, rest)

        "exists:" <> rest ->
          exists_error(field, value, rest)

        "array" ->
          if is_nil(value) or is_list(value) or is_map(value),
            do: [],
            else: ["The #{field} field must be an array."]

        "filled" ->
          if blank?(value), do: ["The #{field} field must have a value."], else: []

        "same:" <> other_field ->
          other = Map.get(data, other_field) || Map.get(data, String.to_atom(other_field))

          if to_string(value || "") == to_string(other || ""),
            do: [],
            else: ["The #{field} and #{other_field} must match."]

        "between:" <> rest ->
          case String.split(rest, ",") do
            [a, b] ->
              min = String.to_integer(String.trim(a))
              max = String.to_integer(String.trim(b))

              cond do
                is_binary(value) and (String.length(value) < min or String.length(value) > max) ->
                  ["The #{field} field must be between #{min} and #{max} characters."]

                is_integer(value) and (value < min or value > max) ->
                  ["The #{field} field must be between #{min} and #{max}."]

                true ->
                  []
              end

            _ ->
              []
          end

        "digits:" <> n ->
          len = String.to_integer(n)

          if is_binary(value) and Regex.match?(~r/^\d+$/, value) and String.length(value) == len,
            do: [],
            else: ["The #{field} field must be #{len} digits."]

        "size:" <> n ->
          size = String.to_integer(n)

          cond do
            is_binary(value) and String.length(value) == size -> []
            is_list(value) and length(value) == size -> []
            true -> ["The #{field} field must be #{size}."]
          end

        other ->
          custom_rule(field, value, other)
      end
    end)
  end

  defp unique_error(_field, nil, _), do: []
  defp unique_error(_field, "", _), do: []

  defp unique_error(field, value, rest) do
    {table, column, ignore_id} = parse_table_column(rest, field)

    q =
      Laravex.Database.Query.table(table)
      |> Laravex.Database.Query.where(column, value)

    q =
      if ignore_id do
        Laravex.Database.Query.where(q, "id", "!=", ignore_id)
      else
        q
      end

    if Laravex.Database.Query.exists?(q) do
      ["The #{field} has already been taken."]
    else
      []
    end
  rescue
    _ -> []
  end

  defp exists_error(_field, nil, _), do: []
  defp exists_error(_field, "", _), do: []

  defp exists_error(field, value, rest) do
    {table, column, _} = parse_table_column(rest, field)

    exists? =
      Laravex.Database.Query.table(table)
      |> Laravex.Database.Query.where(column, value)
      |> Laravex.Database.Query.exists?()

    if exists?, do: [], else: ["The selected #{field} is invalid."]
  rescue
    _ -> ["The selected #{field} is invalid."]
  end

  defp parse_table_column(rest, field) do
    parts = String.split(rest, ",")

    table = Enum.at(parts, 0) || field
    column = Enum.at(parts, 1) || field
    ignore = Enum.at(parts, 2)
    {table, column, ignore}
  end

  defp custom_rule(field, value, rule_name) do
    mod_name = "App.Rules." <> Macro.camelize(to_string(rule_name))

    mod =
      try do
        String.to_existing_atom("Elixir." <> mod_name)
      rescue
        ArgumentError -> Module.concat([mod_name])
      end

    run_rule_module(field, value, %{}, mod)
  end

  defp run_rule_module(field, value, data, mod) do
    case Code.ensure_loaded(mod) do
      {:module, ^mod} ->
        cond do
          function_exported?(mod, :passes?, 3) ->
            if mod.passes?(field, value, data), do: [], else: [rule_message(mod)]

          function_exported?(mod, :passes?, 2) ->
            if mod.passes?(field, value), do: [], else: [rule_message(mod)]

          function_exported?(mod, :validate, 3) ->
            case mod.validate(field, value, data) do
              :ok -> []
              {:error, msg} -> [msg]
              true -> []
              false -> [rule_message(mod)]
              _ -> []
            end

          true ->
            []
        end

      _ ->
        []
    end
  end

  defp rule_message(mod) do
    cond do
      function_exported?(mod, :message, 0) -> mod.message()
      true -> "validation failed"
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end

defmodule Laravex.Validation.Rule do
  @moduledoc """
  Custom validation rule behaviour (Laravel `ValidationRule` / `Rule` objects).

      defmodule App.Rules.Uppercase do
        @behaviour Laravex.Validation.Rule
        def passes?(_attr, value), do: is_binary(value) and value == String.upcase(value)
        def message, do: "must be uppercase"
      end

  Use in rules as a module atom or list entry:

      %{"code" => ["required", App.Rules.Uppercase]}
  """

  @callback passes?(attribute :: String.t(), value :: term()) :: boolean()
  @callback message() :: String.t()
  @optional_callbacks message: 0
end

defmodule Laravex.Http.FormRequest do
  @moduledoc """
  Base form request behaviour.

  Attach via route opts: `form_request: App.Http.Requests.StorePost`.
  """

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
          {:ok, validated, request} ->
            request = %{request | validated: validated}
            Process.put(:laravex_request, request)
            {:ok, request}

          {:error, errors, request} ->
            {:error, errors, request}
        end
      end

      defoverridable authorize: 1
    end
  end

  def resolve(request, form_mod) when is_atom(form_mod) do
    case form_mod.validate_request(request) do
      {:ok, request} ->
        request

      {:error, errors, request} ->
        if Laravex.Http.Request.wants_json?(request) or Laravex.Http.Request.ajax?(request) do
          raise Laravex.Validation.Failed, errors: errors, request: request
        else
          raise Laravex.Validation.Failed, errors: errors, request: request
        end
    end
  end
end
