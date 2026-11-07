defmodule Laravex.Mail.Mailer do
  @moduledoc "Mail manager: log and array drivers."

  @table :laravex_mail_array

  def ensure do
    if :ets.whereis(@table) == :undefined do
      try do
        :ets.new(@table, [:named_table, :public, :bag])
      rescue
        ArgumentError -> :ok
      end
    end

    :ok
  end

  def send(mailable) do
    ensure()
    driver = Laravex.Config.Repository.get("mail.default", "log")
    message = normalize(mailable)

    if Application.get_env(:laravex, :mail_fake, false) or driver == "array" do
      :ets.insert(@table, {:mail, message})
    end

    case driver do
      "array" ->
        :ok

      "log" ->
        Laravex.Log.Logger.info("Mail sent", message)
        :ok

      _ ->
        Laravex.Log.Logger.info("Mail sent via #{driver}", message)
        :ok
    end
  end

  def sent do
    ensure()
    :ets.lookup(@table, :mail) |> Enum.map(fn {:mail, m} -> m end)
  end

  def fake do
    ensure()
    Application.put_env(:laravex, :mail_fake, true)
    :ok
  end

  def assert_sent(fun) when is_function(fun, 1) do
    Enum.any?(sent(), fun)
  end

  defp normalize(%{to: _, subject: _} = m), do: Map.new(m)

  defp normalize(mod) when is_atom(mod) do
    %{
      to: apply(mod, :to, []),
      subject: apply(mod, :subject, []),
      body: if(function_exported?(mod, :content, 0), do: mod.content(), else: "")
    }
  end
end

defmodule Laravex.Mail.Mailable do
  defmacro __using__(_opts) do
    quote do
      def send, do: Laravex.Mail.Mailer.send(__MODULE__)
    end
  end
end
