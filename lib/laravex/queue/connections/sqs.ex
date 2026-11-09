defmodule Laravex.Queue.Connections.Sqs do
  @moduledoc "SQS queue driver via Req + AWS SigV4 (`QUEUE_CONNECTION=sqs`)."
  @behaviour Laravex.Queue.ConnectionAdapter

  @impl true
  def push(job_mod, args, opts) do
    if Keyword.get(opts, :should_queue?, true) do
      payload =
        %{
          "job" => Atom.to_string(job_mod),
          "args" => Laravex.Queue.Worker.encode_args(args),
          "tries" => Keyword.get(opts, :tries, 1),
          "backoff" => Keyword.get(opts, :backoff, 0)
        }
        |> Laravex.Support.JSON.encode!()

      queue_url = queue_url(opts)
      body = URI.encode_query(%{"Action" => "SendMessage", "MessageBody" => payload, "Version" => "2012-11-05"})
      headers = [{~c"content-type", ~c"application/x-www-form-urlencoded"}]
      signed = Laravex.Support.Aws.sign_headers(:post, queue_url, "sqs", headers, body)

      case Req.post(queue_url, body: body, headers: charlist_to_headers(signed)) do
        {:ok, %{status: status}} when status in 200..299 -> :ok
        {:ok, %{status: status, body: resp}} -> raise "SQS push failed (#{status}): #{inspect(resp)}"
        {:error, reason} -> raise "SQS push error: #{inspect(reason)}"
      end
    else
      Laravex.Queue.Worker.push_sync(job_mod, args, opts)
    end
  end

  def pop(opts \\ []) do
    queue_url = queue_url(opts)
    wait = Keyword.get(opts, :wait, 1)

    body =
      URI.encode_query(%{
        "Action" => "ReceiveMessage",
        "MaxNumberOfMessages" => "1",
        "WaitTimeSeconds" => to_string(wait),
        "Version" => "2012-11-05"
      })

    headers = [{~c"content-type", ~c"application/x-www-form-urlencoded"}]
    signed = Laravex.Support.Aws.sign_headers(:post, queue_url, "sqs", headers, body)

    case Req.post(queue_url, body: body, headers: charlist_to_headers(signed)) do
      {:ok, %{status: 200, body: resp}} ->
        case extract_body(resp) do
          nil -> :error
          message -> {:ok, message}
        end

      _ ->
        :error
    end
  end

  defp queue_url(opts) do
    Keyword.get(opts, :url) ||
      System.get_env("SQS_QUEUE_URL") ||
      Laravex.Config.Repository.get("queue.connections.sqs.prefix") ||
      raise "SQS_QUEUE_URL (or queue.connections.sqs.prefix) is required"
  end

  defp charlist_to_headers(headers) do
    Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp extract_body(body) when is_binary(body) do
    case Regex.run(~r/<Body>(.*?)<\/Body>/s, body) do
      [_, msg] -> html_decode(msg)
      _ -> nil
    end
  end

  defp extract_body(_), do: nil

  defp html_decode(str) do
    str
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&amp;", "&")
  end
end
