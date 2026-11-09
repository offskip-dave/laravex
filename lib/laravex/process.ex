defmodule Laravex.Process do
  @moduledoc """
  Laravel Process lite — fluent shell command runner with fakes.

      Laravex.Process.run(["echo", "hi"])
      Laravex.Process.fake(fn _cmd -> %{exit_code: 0, output: "ok", error: ""} end)
  """

  @fake_key :laravex_process_fake

  defstruct command: [], cwd: nil, env: [], timeout: 30_000

  def command(cmd) when is_binary(cmd), do: %__MODULE__{command: [cmd]}
  def command([_ | _] = cmd), do: %__MODULE__{command: cmd}

  def path(%__MODULE__{} = p, cwd), do: %{p | cwd: cwd}
  def timeout(%__MODULE__{} = p, ms) when is_integer(ms), do: %{p | timeout: ms}
  def env(%__MODULE__{} = p, env) when is_list(env), do: %{p | env: env}

  def run(%__MODULE__{command: [bin | args]} = p) do
    case Elixir.Process.get(@fake_key) do
      fun when is_function(fun, 1) ->
        normalize(fun.([bin | args]))

      _ ->
        opts = [stderr_to_stdout: true]
        opts = if p.cwd, do: Keyword.put(opts, :cd, p.cwd), else: opts
        opts = if p.env != [], do: Keyword.put(opts, :env, p.env), else: opts
        {output, status} = System.cmd(bin, args, opts)
        %{exit_code: status, output: output, error: "", successful?: status == 0}
    end
  end

  def run(cmd) when is_binary(cmd) or is_list(cmd), do: cmd |> command() |> run()

  def fake(fun) when is_function(fun, 1) do
    Elixir.Process.put(@fake_key, fun)
    :ok
  end

  def fake_clear, do: Elixir.Process.delete(@fake_key)

  def assert_ran(expected) do
    case Elixir.Process.get(:laravex_process_ran) do
      list when is_list(list) ->
        unless Enum.any?(list, &(&1 == expected)) do
          raise "Process was not run: #{inspect(expected)}"
        end

        :ok

      _ ->
        raise "No process runs recorded"
    end
  end

  defp normalize(%{exit_code: _} = result), do: Map.put_new(result, :successful?, result.exit_code == 0)
  defp normalize(other) when is_map(other), do: other
end
