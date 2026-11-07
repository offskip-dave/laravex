defmodule Laravex.Auth.Policy do
  @moduledoc """
  Resolves `App.Policies.*Policy` modules for a model/resource and
  maps abilities onto `ability?/user, resource` callbacks.
  """

  def policy_for(%{__struct__: mod}), do: policy_for(mod)
  def policy_for(mod) when is_atom(mod) do
    name = mod |> Module.split() |> List.last()
    Module.concat([App.Policies, name <> "Policy"])
  end

  def policy_for(_), do: nil

  def allows?(user, ability, resource) do
    policy = policy_for(resource)

    cond do
      is_nil(policy) ->
        false

      match?({:module, _}, Code.ensure_loaded(policy)) ->
        call_policy(policy, ability, user, resource)

      true ->
        false
    end
  end

  defp call_policy(policy, ability, user, resource) do
    ability = to_string(ability)
    candidates = [:"#{ability}?", String.to_atom(ability), :"#{ability}"]

    Enum.find_value(candidates, false, fn fun ->
      cond do
        function_exported?(policy, fun, 2) ->
          apply(policy, fun, [user, resource])

        function_exported?(policy, fun, 1) and is_nil(resource) ->
          apply(policy, fun, [user])

        true ->
          nil
      end
    end) || false
  end
end
