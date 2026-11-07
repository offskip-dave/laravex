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

  def validate(data, rules, opts \\ []) when is_map(data) and is_map(rules) do
    {rules, excluded} = apply_exclusions(data, rules)
    rules = expand_nested_rules(data, rules)

    errors =
      Enum.reduce(rules, %{}, fn {field, rule_spec}, acc ->
        field = to_string(field)
        value = field_value(data, field)
        field_errors = check(field, value, normalize_rules(rule_spec), data, opts)

        if field_errors == [] do
          acc
        else
          Map.put(acc, field, field_errors)
        end
      end)

    if map_size(errors) == 0 do
      validated =
        data
        |> only_rule_keys(rules)
        |> Map.reject(fn {k, _} -> MapSet.member?(excluded, to_string(k)) end)

      {:ok, validated}
    else
      {:error, errors}
    end
  end

  def validate!(data, rules, opts \\ []) do
    case validate(data, rules, opts) do
      {:ok, data} -> data
      {:error, errors} -> raise Error, errors: errors
    end
  end

  @doc """
  Validate request params. On failure, flashes `_errors` and `_old`.
  For non-JSON requests, raises `Failed` so the kernel can redirect back.

  Options: `:messages` and `:attributes` maps (FormRequest `messages/0`, `attributes/0`).
  """
  def validate_request(request, rules, opts \\ []) do
    data = Map.merge(request.params, request.files || %{})

    case validate(data, rules, opts) do
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

  def only_rule_keys(data, rules) when is_map(data) and is_map(rules) do
    keys = rules |> Map.keys() |> Enum.map(&to_string/1)

    Enum.reduce(keys, %{}, fn key, acc ->
      if String.contains?(key, ".") do
        case Laravex.Support.Arr.get(data, key, :__missing__) do
          :__missing__ -> acc
          value -> Laravex.Support.Arr.set(acc, key, value)
        end
      else
        cond do
          Map.has_key?(data, key) -> Map.put(acc, key, Map.get(data, key))
          Map.has_key?(data, String.to_atom(key)) -> Map.put(acc, key, Map.get(data, String.to_atom(key)))
          true -> acc
        end
      end
    end)
  end

  defp field_value(data, field) do
    if String.contains?(field, ".") do
      Laravex.Support.Arr.get(data, field)
    else
      Map.get(data, field) || Map.get(data, String.to_atom(field))
    end
  end

  defp apply_exclusions(data, rules) do
    Enum.reduce(rules, {%{}, MapSet.new()}, fn {field, spec}, {kept, excluded} ->
      field = to_string(field)
      list = normalize_rules(spec)
      {exclude_rules, other_rules} = Enum.split_with(list, &exclude_rule?/1)

      if Enum.any?(exclude_rules, &exclude_applies?(&1, data)) do
        {kept, MapSet.put(excluded, field)}
      else
        {Map.put(kept, field, other_rules), excluded}
      end
    end)
  end

  defp exclude_rule?("exclude_if:" <> _), do: true
  defp exclude_rule?("exclude_unless:" <> _), do: true
  defp exclude_rule?("exclude"), do: true
  defp exclude_rule?(_), do: false

  defp exclude_applies?("exclude", _data), do: true

  defp exclude_applies?("exclude_if:" <> rest, data) do
    case String.split(rest, ",", parts: 2) do
      [other, expected] ->
        to_string(field_value(data, String.trim(other)) || "") == String.trim(expected)

      _ ->
        false
    end
  end

  defp exclude_applies?("exclude_unless:" <> rest, data) do
    case String.split(rest, ",", parts: 2) do
      [other, expected] ->
        to_string(field_value(data, String.trim(other)) || "") != String.trim(expected)

      _ ->
        false
    end
  end

  defp exclude_applies?(_, _), do: false

  defp expand_nested_rules(data, rules) do
    Enum.reduce(rules, %{}, fn {field, spec}, acc ->
      field = to_string(field)

      if String.contains?(field, "*") do
        Map.merge(acc, expand_wildcard(data, field, spec))
      else
        Map.put(acc, field, spec)
      end
    end)
  end

  defp expand_wildcard(data, pattern, spec) do
    pattern
    |> concrete_paths(data)
    |> Map.new(fn path -> {path, spec} end)
  end

  defp concrete_paths(pattern, data) do
    do_concrete(String.split(pattern, "."), data, [])
  end

  defp do_concrete([], _data, acc), do: [Enum.join(Enum.reverse(acc), ".")]

  defp do_concrete(["*" | rest], data, acc) when is_list(data) do
    data
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, idx} ->
      do_concrete(rest, item, [to_string(idx) | acc])
    end)
  end

  defp do_concrete(["*" | _rest], _data, _acc), do: []

  defp do_concrete([part | rest], data, acc) when is_map(data) do
    value = Map.get(data, part) || Map.get(data, String.to_atom(part))

    if is_nil(value) and rest != [] do
      []
    else
      do_concrete(rest, value, [part | acc])
    end
  end

  defp do_concrete([part | rest], _data, acc) do
    # Leaf missing parent — still emit path so required can fail
    if rest == [], do: [Enum.join(Enum.reverse([part | acc]), ".")], else: []
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

  defp check(field, value, rules, data, opts) do
    rule_strs = Enum.map(rules, &rule_name/1)

    if "sometimes" in rule_strs and not field_present?(data, field) do
      []
    else
      {bail?, rules} = extract_bail(rules)

      Enum.reduce_while(rules, [], fn rule, acc ->
        msgs =
          check_rule(field, value, rule, data)
          |> Enum.map(&format_error(field, rule_name(rule), &1, opts))

        cond do
          msgs == [] ->
            {:cont, acc}

          bail? ->
            {:halt, acc ++ msgs}

          true ->
            {:cont, acc ++ msgs}
        end
      end)
    end
  end

  defp extract_bail(rules) do
    if Enum.any?(rules, fn r -> rule_name(r) == "bail" end) do
      {true, Enum.reject(rules, fn r -> rule_name(r) == "bail" end)}
    else
      {false, rules}
    end
  end

  defp format_error(field, rule, msg, opts) do
    msgs = stringify_keys(Keyword.get(opts, :messages, %{}))
    attrs = stringify_keys(Keyword.get(opts, :attributes, %{}))
    label = Map.get(attrs, field) || humanize_field(field)

    custom = Map.get(msgs, "#{field}.#{rule}") || Map.get(msgs, field)
    base = if is_binary(custom), do: custom, else: msg

    base
    |> String.replace(":attribute", label)
    |> String.replace("The #{field} ", "The #{label} ")
    |> String.replace("the #{field} ", "the #{label} ")
    |> String.replace("selected #{field} ", "selected #{label} ")
    |> String.replace(" #{field} ", " #{label} ")
    |> String.replace(" #{field}.", " #{label}.")
  end

  defp humanize_field(field) do
    field |> to_string() |> String.replace("_", " ") |> String.replace(".", " ")
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_keys(_), do: %{}

  defp check_rule(field, value, rule, data) do
    case rule do
      mod when is_atom(mod) and mod not in [nil, true, false] ->
        run_rule_module(field, value, data, mod)

      "required" ->
        if blank?(value), do: ["The #{field} field is required."], else: []

          "required_if:" <> rest ->
            conditional_required(field, value, data, rest, :if)

          "required_unless:" <> rest ->
            conditional_required(field, value, data, rest, :unless)

          "required_with:" <> rest ->
            required_with_rule(field, value, data, rest, :any)

          "required_with_all:" <> rest ->
            required_with_rule(field, value, data, rest, :all)

          "required_without:" <> rest ->
            required_without_rule(field, value, data, rest, :any)

          "required_without_all:" <> rest ->
            required_without_rule(field, value, data, rest, :all)

          "prohibited" ->
            if blank?(value), do: [], else: ["The #{field} field is prohibited."]

      "prohibited_if:" <> rest ->
        conditional_prohibited(field, value, data, rest, :if)

      "prohibited_unless:" <> rest ->
        conditional_prohibited(field, value, data, rest, :unless)

      "sometimes" ->
        []

      "date" ->
        if is_nil(value) or blank?(value) or valid_date?(value),
          do: [],
          else: ["The #{field} field must be a valid date."]

      "date_format:" <> format ->
        if is_nil(value) or blank?(value) or match_date_format?(value, format),
          do: [],
          else: ["The #{field} field must match the format #{format}."]

      "string" ->
        if is_nil(value) or is_binary(value),
          do: [],
          else: ["The #{field} field must be a string."]

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
        min_rule(field, value, String.to_integer(n))

      "max:" <> n ->
        max_rule(field, value, String.to_integer(n))

      "integer" ->
        if is_nil(value) or is_integer(value) or
             (is_binary(value) and match?({_, ""}, Integer.parse(value))),
           do: [],
           else: ["The #{field} field must be an integer."]

      "numeric" ->
        if is_nil(value) or numeric?(value),
          do: [],
          else: ["The #{field} field must be a number."]

      "decimal" ->
        decimal_rule(field, value, nil)

      "decimal:" <> rest ->
        decimal_rule(field, value, rest)

      "multiple_of:" <> n ->
        multiple_of_rule(field, value, String.trim(n))

      "boolean" ->
        if value in [true, false, 1, 0, "1", "0", "true", "false", nil],
          do: [],
          else: ["The #{field} field must be true or false."]

      "nullable" ->
        []

      "present" ->
        if field_present?(data, field),
          do: [],
          else: ["The #{field} field must be present."]

      "present_if:" <> rest ->
        conditional_present(field, data, rest, :if)

      "present_unless:" <> rest ->
        conditional_present(field, data, rest, :unless)

      "missing" ->
        if field_present?(data, field),
          do: ["The #{field} field must be missing."],
          else: []

      "missing_if:" <> rest ->
        conditional_missing(field, data, rest, :if)

      "missing_unless:" <> rest ->
        conditional_missing(field, data, rest, :unless)

      "prohibits:" <> rest ->
        prohibits_rule(field, value, data, rest)

      "url" ->
        if is_nil(value) or blank?(value) or valid_url?(value),
          do: [],
          else: ["The #{field} field must be a valid URL."]

      "uuid" ->
        if is_nil(value) or blank?(value) or valid_uuid?(value),
          do: [],
          else: ["The #{field} field must be a valid UUID."]

      "ulid" ->
        if is_nil(value) or blank?(value) or Laravex.Support.Str.is_ulid?(value),
          do: [],
          else: ["The #{field} field must be a valid ULID."]

      "mac_address" ->
        if is_nil(value) or blank?(value) or Laravex.Support.Str.is_mac_address?(value),
          do: [],
          else: ["The #{field} field must be a valid MAC address."]

      "after:" <> other ->
        date_compare_rule(field, value, data, String.trim(other), :after)

      "before:" <> other ->
        date_compare_rule(field, value, data, String.trim(other), :before)

      "after_or_equal:" <> other ->
        date_compare_rule(field, value, data, String.trim(other), :after_or_equal)

      "before_or_equal:" <> other ->
        date_compare_rule(field, value, data, String.trim(other), :before_or_equal)

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

      "mimes:" <> list ->
        mime_ext_rule(field, value, list)

      "extensions:" <> list ->
        mime_ext_rule(field, value, list)

      "mimetypes:" <> list ->
        mimetype_rule(field, value, list)

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

      "required_array_keys:" <> rest ->
        required_array_keys_rule(field, value, rest)

      "doesnt_contain:" <> rest ->
        does_not_contain_rule(field, value, rest)

      "does_not_contain:" <> rest ->
        does_not_contain_rule(field, value, rest)

      "contains:" <> rest ->
        contains_rule(field, value, rest)

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

      "digits_between:" <> rest ->
        case String.split(rest, ",") do
          [a, b] ->
            min = String.to_integer(String.trim(a))
            max = String.to_integer(String.trim(b))

            if is_binary(value) and Regex.match?(~r/^\d+$/, value) and
                 String.length(value) >= min and String.length(value) <= max,
               do: [],
               else: ["The #{field} field must be between #{min} and #{max} digits."]

          _ ->
            []
        end

      "accepted" ->
        if value in [true, 1, "1", "true", "yes", "on"],
          do: [],
          else: ["The #{field} must be accepted."]

      "accepted_if:" <> rest ->
        conditional_accepted(field, value, data, rest, :accepted)

      "declined" ->
        if value in [false, 0, "0", "false", "no", "off"],
          do: [],
          else: ["The #{field} must be declined."]

      "declined_if:" <> rest ->
        conditional_accepted(field, value, data, rest, :declined)

      "distinct" ->
        distinct_rule(field, value)

      "alpha" ->
        if is_nil(value) or blank?(value) or (is_binary(value) and Regex.match?(~r/^\p{L}+$/u, value)),
          do: [],
          else: ["The #{field} field must only contain letters."]

      "alpha_num" ->
        if is_nil(value) or blank?(value) or
             (is_binary(value) and Regex.match?(~r/^[\p{L}0-9]+$/u, value)),
          do: [],
          else: ["The #{field} field must only contain letters and numbers."]

      "alpha_dash" ->
        if is_nil(value) or blank?(value) or
             (is_binary(value) and Regex.match?(~r/^[\p{L}0-9_-]+$/u, value)),
          do: [],
          else: ["The #{field} field must only contain letters, numbers, dashes and underscores."]

      "ascii" ->
        if is_nil(value) or blank?(value) or (is_binary(value) and Regex.match?(~r/^[\x00-\x7F]*$/, value)),
          do: [],
          else: ["The #{field} field must contain only ASCII characters."]

      "hex_color" ->
        if is_nil(value) or blank?(value) or
             (is_binary(value) and Regex.match?(~r/^#?(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/, value)),
          do: [],
          else: ["The #{field} field must be a valid hexadecimal color."]

      "different:" <> other_field ->
        other = Map.get(data, other_field) || Map.get(data, String.to_atom(other_field))

        if to_string(value || "") != to_string(other || ""),
          do: [],
          else: ["The #{field} and #{other_field} must be different."]

      "not_in:" <> list ->
        denied = String.split(list, ",")

        if is_nil(value) or to_string(value) not in denied,
          do: [],
          else: ["The selected #{field} is invalid."]

      "gt:" <> other ->
        compare_numeric_rule(field, value, data, String.trim(other), :gt)

      "gte:" <> other ->
        compare_numeric_rule(field, value, data, String.trim(other), :gte)

      "lt:" <> other ->
        compare_numeric_rule(field, value, data, String.trim(other), :lt)

      "lte:" <> other ->
        compare_numeric_rule(field, value, data, String.trim(other), :lte)

      "starts_with:" <> list ->
        prefixes = String.split(list, ",")

        if is_nil(value) or blank?(value) or
             Enum.any?(prefixes, &String.starts_with?(to_string(value), &1)),
           do: [],
           else: ["The #{field} field must start with one of the following: #{list}."]

      "ends_with:" <> list ->
        suffixes = String.split(list, ",")

        if is_nil(value) or blank?(value) or
             Enum.any?(suffixes, &String.ends_with?(to_string(value), &1)),
           do: [],
           else: ["The #{field} field must end with one of the following: #{list}."]

      "doesnt_start_with:" <> list ->
        prefixes = String.split(list, ",")

        if is_nil(value) or blank?(value) or
             not Enum.any?(prefixes, &String.starts_with?(to_string(value), &1)),
           do: [],
           else: ["The #{field} field must not start with one of the following: #{list}."]

      "doesnt_end_with:" <> list ->
        suffixes = String.split(list, ",")

        if is_nil(value) or blank?(value) or
             not Enum.any?(suffixes, &String.ends_with?(to_string(value), &1)),
           do: [],
           else: ["The #{field} field must not end with one of the following: #{list}."]

      "lowercase" ->
        if is_nil(value) or blank?(value) or to_string(value) == String.downcase(to_string(value)),
          do: [],
          else: ["The #{field} field must be lowercase."]

      "uppercase" ->
        if is_nil(value) or blank?(value) or to_string(value) == String.upcase(to_string(value)),
          do: [],
          else: ["The #{field} field must be uppercase."]

      "size:" <> n ->
        size = String.to_integer(n)

        cond do
          is_binary(value) and String.length(value) == size -> []
          is_list(value) and length(value) == size -> []
          true -> ["The #{field} field must be #{size}."]
        end

      "bail" ->
        []

      "json" ->
        if is_nil(value) or blank?(value) or valid_json?(value),
          do: [],
          else: ["The #{field} field must be a valid JSON string."]

      "ip" ->
        if is_nil(value) or blank?(value) or valid_ip?(value),
          do: [],
          else: ["The #{field} field must be a valid IP address."]

      "ipv4" ->
        if is_nil(value) or blank?(value) or valid_ipv4?(value),
          do: [],
          else: ["The #{field} field must be a valid IPv4 address."]

      "ipv6" ->
        if is_nil(value) or blank?(value) or valid_ipv6?(value),
          do: [],
          else: ["The #{field} field must be a valid IPv6 address."]

      "password" ->
        password_rule(field, value, [])

      "password:" <> rest ->
        flags = rest |> String.split(",") |> Enum.map(&String.trim/1)
        password_rule(field, value, flags)

      other ->
        custom_rule(field, value, other)
    end
  end

  defp password_rule(_field, value, _flags) when is_nil(value) or value == "", do: []

  defp password_rule(field, value, flags) do
    value = to_string(value)
    min = password_min(flags)

    []
    |> then(fn errs ->
      if String.length(value) < min,
        do: ["The #{field} field must be at least #{min} characters." | errs],
        else: errs
    end)
    |> then(fn errs ->
      if "letters" in flags and not Regex.match?(~r/\p{L}/u, value),
        do: ["The #{field} field must contain at least one letter." | errs],
        else: errs
    end)
    |> then(fn errs ->
      if "mixed" in flags and
           not (Regex.match?(~r/\p{Ll}/u, value) and Regex.match?(~r/\p{Lu}/u, value)),
         do: ["The #{field} field must contain both uppercase and lowercase letters." | errs],
         else: errs
    end)
    |> then(fn errs ->
      if "numbers" in flags and not Regex.match?(~r/\d/, value),
        do: ["The #{field} field must contain at least one number." | errs],
        else: errs
    end)
    |> then(fn errs ->
      if "symbols" in flags and not Regex.match?(~r/[^\p{L}\d\s]/u, value),
        do: ["The #{field} field must contain at least one symbol." | errs],
        else: errs
    end)
    |> Enum.reverse()
  end

  defp password_min(flags) do
    case Enum.find_index(flags, &(&1 == "min" or String.starts_with?(&1, "min"))) do
      nil ->
        8

      idx ->
        case Enum.at(flags, idx) do
          "min" ->
            case Enum.at(flags, idx + 1) do
              n when is_binary(n) ->
                case Integer.parse(n) do
                  {i, _} -> i
                  _ -> 8
                end

              _ ->
                8
            end

          "min:" <> n ->
            String.to_integer(String.trim(n))

          "min," <> n ->
            String.to_integer(String.trim(n))

          _ ->
            8
        end
    end
  end

  defp valid_json?(value) when is_binary(value) do
    case Laravex.Support.JSON.decode(value) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp valid_json?(_), do: false

  defp valid_ip?(value), do: valid_ipv4?(value) or valid_ipv6?(value)

  defp valid_ipv4?(value) when is_binary(value) do
    case :inet.parse_ipv4_address(String.to_charlist(value)) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp valid_ipv4?(_), do: false

  defp valid_ipv6?(value) when is_binary(value) do
    case :inet.parse_ipv6_address(String.to_charlist(value)) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp valid_ipv6?(_), do: false

  defp compare_numeric_rule(field, value, data, other, op) do
    if is_nil(value) or blank?(value) do
      []
    else
      other_val =
        cond do
          field_present?(data, other) ->
            Map.get(data, other) || Map.get(data, String.to_atom(other))

          match?({_, ""}, Float.parse(other)) or match?({_, ""}, Integer.parse(other)) ->
            other

          true ->
            Map.get(data, other) || Map.get(data, String.to_atom(other)) || other
        end

      cond do
        not (numeric?(value) and numeric?(other_val)) ->
          []

        op == :gt and to_number(value) > to_number(other_val) ->
          []

        op == :gte and to_number(value) >= to_number(other_val) ->
          []

        op == :lt and to_number(value) < to_number(other_val) ->
          []

        op == :lte and to_number(value) <= to_number(other_val) ->
          []

        true ->
          label =
            case op do
              :gt -> "greater than"
              :gte -> "greater than or equal to"
              :lt -> "less than"
              :lte -> "less than or equal to"
            end

          ["The #{field} field must be #{label} #{other}."]
      end
    end
  end

  defp rule_name(rule) when is_binary(rule), do: rule |> String.split(":", parts: 2) |> hd()
  defp rule_name(rule) when is_atom(rule), do: to_string(rule)
  defp rule_name(_), do: ""

  defp field_present?(data, field) do
    if String.contains?(to_string(field), ".") do
      Laravex.Support.Arr.get(data, field, :__missing__) != :__missing__
    else
      Map.has_key?(data, field) or Map.has_key?(data, String.to_atom(field))
    end
  end

  defp data_get(data, field), do: field_value(data, to_string(field))

  defp filled_field?(data, field) do
    not blank?(field_value(data, String.trim(to_string(field))))
  end

  defp required_with_rule(field, value, data, rest, mode) do
    others = rest |> String.split(",") |> Enum.map(&String.trim/1)

    present? =
      case mode do
        :any -> Enum.any?(others, &filled_field?(data, &1))
        :all -> Enum.all?(others, &filled_field?(data, &1))
      end

    if present? and blank?(value) do
      ["The #{field} field is required when #{Enum.join(others, " / ")} is present."]
    else
      []
    end
  end

  defp required_without_rule(field, value, data, rest, mode) do
    others = rest |> String.split(",") |> Enum.map(&String.trim/1)

    missing? =
      case mode do
        :any -> Enum.any?(others, &(not filled_field?(data, &1)))
        :all -> Enum.all?(others, &(not filled_field?(data, &1)))
      end

    if missing? and blank?(value) do
      ["The #{field} field is required when #{Enum.join(others, " / ")} is not present."]
    else
      []
    end
  end

  defp conditional_required(field, value, data, rest, mode) do
    case String.split(rest, ",", parts: 2) do
      [other, expected] ->
        other = String.trim(other)
        expected = String.trim(expected)
        other_val = to_string(data_get(data, other) || "")
        match? = other_val == expected

        required? =
          case mode do
            :if -> match?
            :unless -> not match?
          end

        if required? and blank?(value) do
          msg =
            case mode do
              :if -> "The #{field} field is required when #{other} is #{expected}."
              :unless -> "The #{field} field is required unless #{other} is #{expected}."
            end

          [msg]
        else
          []
        end

      _ ->
        []
    end
  end

  defp conditional_prohibited(field, value, data, rest, mode) do
    case String.split(rest, ",", parts: 2) do
      [other, expected] ->
        other = String.trim(other)
        expected = String.trim(expected)
        other_val = to_string(data_get(data, other) || "")
        match? = other_val == expected

        prohibited? =
          case mode do
            :if -> match?
            :unless -> not match?
          end

        if prohibited? and not blank?(value) do
          ["The #{field} field is prohibited."]
        else
          []
        end

      _ ->
        []
    end
  end

  defp conditional_present(field, data, rest, mode) do
    case String.split(rest, ",", parts: 2) do
      [other, expected] ->
        other = String.trim(other)
        expected = String.trim(expected)
        other_val = to_string(data_get(data, other) || "")
        match? = other_val == expected

        required? =
          case mode do
            :if -> match?
            :unless -> not match?
          end

        if required? and not field_present?(data, field) do
          ["The #{field} field must be present."]
        else
          []
        end

      _ ->
        []
    end
  end

  defp conditional_missing(field, data, rest, mode) do
    case String.split(rest, ",", parts: 2) do
      [other, expected] ->
        other = String.trim(other)
        expected = String.trim(expected)
        other_val = to_string(data_get(data, other) || "")
        match? = other_val == expected

        must_miss? =
          case mode do
            :if -> match?
            :unless -> not match?
          end

        if must_miss? and field_present?(data, field) do
          ["The #{field} field must be missing."]
        else
          []
        end

      _ ->
        []
    end
  end

  defp prohibits_rule(field, value, data, rest) do
    if blank?(value) do
      []
    else
      others = rest |> String.split(",") |> Enum.map(&String.trim/1)

      Enum.flat_map(others, fn other ->
        if field_present?(data, other) and filled_field?(data, other) do
          ["The #{other} field is prohibited when #{field} is present."]
        else
          []
        end
      end)
    end
  end

  defp required_array_keys_rule(field, value, rest) do
    keys = rest |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    cond do
      is_nil(value) or blank?(value) ->
        []

      is_map(value) ->
        missing =
          Enum.reject(keys, fn k ->
            Map.has_key?(value, k) or Map.has_key?(value, String.to_atom(k))
          end)

        if missing == [],
          do: [],
          else: ["The #{field} field must contain entries for: #{Enum.join(keys, ", ")}."]

      is_list(value) ->
        # Associative list of {k,v} pairs or list of required key names present as values
        present =
          value
          |> Enum.flat_map(fn
            {k, _} -> [to_string(k)]
            k -> [to_string(k)]
          end)

        if Enum.all?(keys, &(&1 in present)),
          do: [],
          else: ["The #{field} field must contain entries for: #{Enum.join(keys, ", ")}."]

      true ->
        ["The #{field} field must be an array."]
    end
  end

  defp does_not_contain_rule(field, value, rest) do
    denied = rest |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    cond do
      is_nil(value) or blank?(value) ->
        []

      contains_any?(value, denied) ->
        ["The #{field} field contains a prohibited value."]

      true ->
        []
    end
  end

  defp contains_rule(field, value, rest) do
    needed = rest |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    cond do
      is_nil(value) or blank?(value) ->
        []

      contains_any?(value, needed) ->
        []

      true ->
        ["The #{field} field must contain one of the following: #{Enum.join(needed, ", ")}."]
    end
  end

  defp contains_any?(value, needles) when is_binary(value) do
    Enum.any?(needles, &String.contains?(value, &1))
  end

  defp contains_any?(value, needles) when is_list(value) do
    stringified = Enum.map(value, &to_string/1)
    Enum.any?(needles, &(&1 in stringified))
  end

  defp contains_any?(value, needles) when is_map(value) do
    vals = value |> Map.values() |> Enum.map(&to_string/1)
    keys = value |> Map.keys() |> Enum.map(&to_string/1)
    Enum.any?(needles, &(&1 in vals or &1 in keys))
  end

  defp contains_any?(_, _), do: false

  defp valid_date?(value) when is_binary(value) do
    cond do
      match?({:ok, _}, Date.from_iso8601(value)) ->
        true

      match?({:ok, _, _}, DateTime.from_iso8601(value)) ->
        true

      Regex.match?(~r/^\d{4}-\d{2}-\d{2}/, value) ->
        case Date.from_iso8601(String.slice(value, 0, 10)) do
          {:ok, _} -> true
          _ -> false
        end

      true ->
        false
    end
  end

  defp valid_date?(%Date{}), do: true
  defp valid_date?(%DateTime{}), do: true
  defp valid_date?(%NaiveDateTime{}), do: true
  defp valid_date?(_), do: false

  defp match_date_format?(value, "Y-m-d") when is_binary(value),
    do: match?({:ok, _}, Date.from_iso8601(value))

  defp match_date_format?(value, "Y-m-d H:i:s") when is_binary(value) do
    case NaiveDateTime.from_iso8601(String.replace(value, " ", "T")) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp match_date_format?(value, format) when is_binary(value) and is_binary(format) do
    # Fallback: treat as ISO-ish when format unrecognized
    valid_date?(value)
  end

  defp match_date_format?(_, _), do: false

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

  defp min_rule(field, %Laravex.Http.UploadedFile{size: size}, min) when is_integer(size) do
    # Laravel max/min for files are kilobytes
    if div(size, 1024) < min,
      do: ["The #{field} must be at least #{min} kilobytes."],
      else: []
  end

  defp min_rule(field, value, min) do
    cond do
      is_binary(value) and String.length(value) < min ->
        ["The #{field} field must be at least #{min} characters."]

      is_integer(value) and value < min ->
        ["The #{field} field must be at least #{min}."]

      numeric?(value) and to_number(value) < min ->
        ["The #{field} field must be at least #{min}."]

      true ->
        []
    end
  end

  defp max_rule(field, %Laravex.Http.UploadedFile{size: size}, max) when is_integer(size) do
    if div(size, 1024) > max,
      do: ["The #{field} must not be greater than #{max} kilobytes."],
      else: []
  end

  defp max_rule(field, value, max) do
    cond do
      is_binary(value) and String.length(value) > max ->
        ["The #{field} field must not be greater than #{max} characters."]

      is_integer(value) and value > max ->
        ["The #{field} field must not be greater than #{max}."]

      numeric?(value) and to_number(value) > max ->
        ["The #{field} field must not be greater than #{max}."]

      true ->
        []
    end
  end

  defp mime_ext_rule(_field, nil, _), do: []
  defp mime_ext_rule(_field, "", _), do: []

  defp mime_ext_rule(field, %Laravex.Http.UploadedFile{} = file, list) do
    allowed =
      list |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.map(&String.downcase/1)

    ext = Laravex.Http.UploadedFile.extension(file)

    if ext in allowed,
      do: [],
      else: ["The #{field} field must be a file of type: #{Enum.join(allowed, ", ")}."]
  end

  defp mime_ext_rule(field, _, _), do: ["The #{field} field must be a file."]

  defp mimetype_rule(_field, nil, _), do: []
  defp mimetype_rule(_field, "", _), do: []

  defp mimetype_rule(field, %Laravex.Http.UploadedFile{} = file, list) do
    allowed =
      list |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.map(&String.downcase/1)

    type = String.downcase(to_string(file.content_type || ""))

    if type in allowed or
         Enum.any?(allowed, &String.starts_with?(type, String.trim_trailing(&1, "/*") <> "/")),
       do: [],
       else: ["The #{field} field must be a file of type: #{Enum.join(allowed, ", ")}."]
  end

  defp mimetype_rule(field, _, _), do: ["The #{field} field must be a file."]

  defp numeric?(value) when is_number(value), do: true

  defp numeric?(value) when is_binary(value) do
    case Float.parse(value) do
      {_, ""} -> true
      _ -> match?({_, ""}, Integer.parse(value))
    end
  end

  defp numeric?(_), do: false

  defp decimal_rule(_field, value, _rest) when is_nil(value) or value == "", do: []

  defp decimal_rule(field, value, rest) do
    cond do
      not numeric?(value) ->
        ["The #{field} field must be a number."]

      is_nil(rest) or rest == "" ->
        []

      true ->
        case String.split(rest, ",") do
          [min_places] ->
            places = String.to_integer(String.trim(min_places))

            if decimal_places(value) == places,
              do: [],
              else: ["The #{field} field must have #{places} decimal places."]

          [min_places, max_places] ->
            min_p = String.to_integer(String.trim(min_places))
            max_p = String.to_integer(String.trim(max_places))
            places = decimal_places(value)

            if places >= min_p and places <= max_p,
              do: [],
              else: ["The #{field} field must have between #{min_p} and #{max_p} decimal places."]

          _ ->
            []
        end
    end
  end

  defp decimal_places(value) when is_integer(value), do: 0

  defp decimal_places(value) when is_float(value) do
    value
    |> :erlang.float_to_binary([{:decimals, 10}])
    |> String.trim_trailing("0")
    |> then(fn s ->
      case String.split(s, ".") do
        [_, frac] -> String.length(frac)
        _ -> 0
      end
    end)
  end

  defp decimal_places(value) when is_binary(value) do
    case String.split(String.trim(value), ".") do
      [_, frac] -> String.length(frac)
      _ -> 0
    end
  end

  defp multiple_of_rule(_field, value, _n) when is_nil(value) or value == "", do: []

  defp multiple_of_rule(field, value, n) do
    with true <- numeric?(value),
         {divisor, _} <- Float.parse(n),
         true <- divisor != 0 do
      num = to_number(value) * 1.0
      rem = :math.fmod(num, divisor)

      if abs(rem) < 1.0e-9 or abs(abs(rem) - abs(divisor)) < 1.0e-9,
        do: [],
        else: ["The #{field} field must be a multiple of #{n}."]
    else
      _ -> ["The #{field} field must be a multiple of #{n}."]
    end
  end

  defp to_number(value) when is_integer(value), do: value
  defp to_number(value) when is_float(value), do: value

  defp to_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {i, ""} ->
        i

      _ ->
        case Float.parse(value) do
          {f, ""} -> f
          _ -> 0
        end
    end
  end

  defp valid_url?(value) when is_binary(value) do
    uri = URI.parse(value)
    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != ""
  end

  defp valid_url?(_), do: false

  defp valid_uuid?(value) when is_binary(value) do
    Regex.match?(
      ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/,
      value
    )
  end

  defp valid_uuid?(_), do: false

  defp date_compare_rule(_field, nil, _data, _other, _op), do: []
  defp date_compare_rule(_field, "", _data, _other, _op), do: []

  defp date_compare_rule(field, value, data, other, op) do
    left = parse_comparable_date(value)
    right = parse_comparable_date(data_get(data, other) || other)
    cmp = if left && right, do: Date.compare(left, right), else: nil

    cond do
      is_nil(cmp) ->
        []

      op == :after and cmp == :gt ->
        []

      op == :before and cmp == :lt ->
        []

      op == :after_or_equal and cmp in [:gt, :eq] ->
        []

      op == :before_or_equal and cmp in [:lt, :eq] ->
        []

      op == :after ->
        ["The #{field} field must be a date after #{other}."]

      op == :before ->
        ["The #{field} field must be a date before #{other}."]

      op == :after_or_equal ->
        ["The #{field} field must be a date after or equal to #{other}."]

      op == :before_or_equal ->
        ["The #{field} field must be a date before or equal to #{other}."]

      true ->
        []
    end
  end

  defp conditional_accepted(field, value, data, rest, mode) do
    case String.split(rest, ",", parts: 2) do
      [other, expected] ->
        other_val = to_string(data_get(data, String.trim(other)) || "")

        if other_val == String.trim(expected) do
          case mode do
            :accepted ->
              if value in [true, 1, "1", "true", "yes", "on"],
                do: [],
                else: ["The #{field} must be accepted."]

            :declined ->
              if value in [false, 0, "0", "false", "no", "off"],
                do: [],
                else: ["The #{field} must be declined."]
          end
        else
          []
        end

      _ ->
        []
    end
  end

  defp distinct_rule(_field, value) when is_nil(value) or value == "", do: []

  defp distinct_rule(field, value) when is_list(value) do
    normalized = Enum.map(value, &to_string/1)

    if length(normalized) == length(Enum.uniq(normalized)),
      do: [],
      else: ["The #{field} field has a duplicate value."]
  end

  defp distinct_rule(_field, _), do: []

  defp parse_comparable_date(%Date{} = d), do: d
  defp parse_comparable_date(%DateTime{} = d), do: DateTime.to_date(d)
  defp parse_comparable_date(%NaiveDateTime{} = d), do: NaiveDateTime.to_date(d)

  defp parse_comparable_date(value) when is_binary(value) do
    cond do
      match?({:ok, _}, Date.from_iso8601(value)) ->
        elem(Date.from_iso8601(value), 1)

      match?({:ok, _, _}, DateTime.from_iso8601(value)) ->
        {:ok, dt, _} = DateTime.from_iso8601(value)
        DateTime.to_date(dt)

      Regex.match?(~r/^\d{4}-\d{2}-\d{2}/, value) ->
        case Date.from_iso8601(String.slice(value, 0, 10)) do
          {:ok, d} -> d
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp parse_comparable_date(_), do: nil
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

      def messages, do: %{"email.required" => "We need your :attribute"}
      def attributes, do: %{"email" => "email address"}
  """

  @callback rules() :: map()
  @callback authorize(request :: map()) :: boolean()
  @callback messages() :: map()
  @callback attributes() :: map()
  @optional_callbacks messages: 0, attributes: 0

  defmacro __using__(_opts) do
    quote do
      @behaviour Laravex.Http.FormRequest

      def authorize(_request), do: true
      def messages, do: %{}
      def attributes, do: %{}

      def validate_request(request) do
        unless authorize(request),
          do: raise(Laravex.Http.HttpException, status: 403, message: "Forbidden")

        opts = [messages: messages(), attributes: attributes()]

        case Laravex.Validation.validate_request(request, rules(), opts) do
          {:ok, validated, request} ->
            request = %{request | validated: validated}
            Process.put(:laravex_request, request)
            {:ok, request}

          {:error, errors, request} ->
            {:error, errors, request}
        end
      end

      defoverridable authorize: 1, messages: 0, attributes: 0
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
