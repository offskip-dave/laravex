defmodule Laravex.Mail.Transports.Ses do
  @moduledoc "AWS SES mail transport via Req + SigV4."
  @behaviour Laravex.Mail.Transport

  @impl true
  def send(message) do
    region = System.get_env("AWS_DEFAULT_REGION") || "us-east-1"
    url = "https://email.#{region}.amazonaws.com/"
    from = message[:from] || message["from"] || raise "SES requires :from"
    to = List.wrap(message[:to] || message["to"]) |> Enum.join(", ")
    subject = message[:subject] || message["subject"] || ""
    body = message[:html] || message["html"] || message[:text] || message["text"] || ""

    form =
      URI.encode_query(%{
        "Action" => "SendEmail",
        "Source" => to_string(from),
        "Destination.ToAddresses.member.1" => to,
        "Message.Subject.Data" => subject,
        "Message.Body.Html.Data" => body,
        "Version" => "2010-12-01"
      })

    headers = [{~c"content-type", ~c"application/x-www-form-urlencoded"}]
    signed = Laravex.Support.Aws.sign_headers(:post, url, "ses", headers, form)

    case Req.post(url, body: form, headers: Enum.map(signed, fn {k, v} -> {to_string(k), to_string(v)} end)) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status, body: resp}} -> raise "SES send failed (#{status}): #{inspect(resp)}"
      {:error, reason} -> raise "SES send error: #{inspect(reason)}"
    end
  end
end
