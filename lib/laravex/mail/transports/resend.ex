defmodule Laravex.Mail.Transports.Resend do
  @moduledoc "Resend mail transport via Req."
  @behaviour Laravex.Mail.Transport

  @impl true
  def send(message) do
    key = System.get_env("RESEND_API_KEY") || Laravex.Config.Repository.get("services.resend.key")
    if is_nil(key) or key == "", do: raise("RESEND_API_KEY is required")

    payload = %{
      "from" => message[:from] || message["from"],
      "to" => List.wrap(message[:to] || message["to"]),
      "subject" => message[:subject] || message["subject"] || "",
      "html" => message[:html] || message["html"] || message[:text] || message["text"] || ""
    }

    case Req.post("https://api.resend.com/emails",
           json: payload,
           headers: [{"Authorization", "Bearer #{key}"}]
         ) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> raise "Resend send failed (#{status}): #{inspect(body)}"
      {:error, reason} -> raise "Resend send error: #{inspect(reason)}"
    end
  end
end
