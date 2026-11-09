defmodule Laravex.Mail.Transports.Postmark do
  @moduledoc "Postmark mail transport via Req."
  @behaviour Laravex.Mail.Transport

  @impl true
  def send(message) do
    token = System.get_env("POSTMARK_TOKEN") || Laravex.Config.Repository.get("services.postmark.token")
    if is_nil(token) or token == "", do: raise("POSTMARK_TOKEN is required")

    payload = %{
      "From" => message[:from] || message["from"],
      "To" => List.wrap(message[:to] || message["to"]) |> Enum.join(", "),
      "Subject" => message[:subject] || message["subject"] || "",
      "HtmlBody" => message[:html] || message["html"] || message[:text] || message["text"] || ""
    }

    case Req.post("https://api.postmarkapp.com/email",
           json: payload,
           headers: [{"X-Postmark-Server-Token", token}, {"Accept", "application/json"}]
         ) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: body}} -> raise "Postmark send failed (#{status}): #{inspect(body)}"
      {:error, reason} -> raise "Postmark send error: #{inspect(reason)}"
    end
  end
end
