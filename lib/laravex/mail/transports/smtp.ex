defmodule Laravex.Mail.Transports.Smtp do
  @moduledoc """
  Basic SMTP client via `:gen_tcp` / `:ssl` (no Hex deps).

  Configure `mail.mailers.smtp` (host, port, username, password, `local_domain`).
  """
  @behaviour Laravex.Mail.Transport

  @timeout 30_000

  @impl true
  def send(message) do
    cfg = Laravex.Config.Repository.get("mail.mailers.smtp") || %{}
    host = to_string(Map.get(cfg, "host", "127.0.0.1"))
    port = to_int(Map.get(cfg, "port", 2525))
    user = Map.get(cfg, "username") || Map.get(cfg, :username)
    pass = Map.get(cfg, "password") || Map.get(cfg, :password)
    ehlo = Map.get(cfg, "local_domain") || Map.get(cfg, "local_domain") || "localhost"

    from = Map.get(message, :from_address) || Map.get(message, "from_address") || "hello@example.com"
    to = Map.get(message, :to) || Map.get(message, "to") || raise "SMTP requires a :to address"

    recipients = List.wrap(to) |> Enum.map(&to_string/1)

    body =
      build_body(
        from,
        recipients,
        Map.get(message, :subject) || "",
        Map.get(message, :body) || "",
        Map.get(message, :cc),
        Map.get(message, :bcc)
      )

    with {:ok, socket, kind} <- connect(host, port, cfg),
         :ok <- greet(socket, kind),
         :ok <- speak(socket, kind, "EHLO #{ehlo}"),
         :ok <- maybe_auth(socket, kind, user, pass),
         :ok <- speak(socket, kind, "MAIL FROM:<#{from}>"),
         :ok <- rcpt_all(socket, kind, recipients),
         :ok <- speak(socket, kind, "DATA"),
         :ok <- speak_raw(socket, kind, body <> "\r\n."),
         :ok <- speak(socket, kind, "QUIT"),
         :ok <- close(socket, kind) do
      :ok
    else
      {:error, reason} -> raise "SMTP error: #{inspect(reason)}"
    end
  end

  defp connect(host, port, cfg) do
    scheme = Map.get(cfg, "scheme") || Map.get(cfg, :scheme)
    use_ssl = scheme == "smtps" or port == 465

    if use_ssl do
      case :ssl.connect(to_charlist(host), port, [:binary, active: false], @timeout) do
        {:ok, socket} -> {:ok, socket, :ssl}
        err -> err
      end
    else
      case :gen_tcp.connect(to_charlist(host), port, [:binary, active: false], @timeout) do
        {:ok, socket} -> {:ok, socket, :tcp}
        err -> err
      end
    end
  end

  defp greet(socket, :tcp) do
    case recv_line(socket, :tcp) do
      {:ok, "220" <> _} -> :ok
      {:ok, line} -> {:error, line}
      err -> err
    end
  end

  defp greet(socket, :ssl) do
    case recv_line(socket, :ssl) do
      {:ok, "220" <> _} -> :ok
      {:ok, line} -> {:error, line}
      err -> err
    end
  end

  defp speak(socket, kind, command) do
    _ = send_line(socket, kind, command)

    case recv_line(socket, kind) do
      {:ok, "250" <> _} -> :ok
      {:ok, "354" <> _} -> :ok
      {:ok, "221" <> _} -> :ok
      {:ok, "334" <> _} -> :ok
      {:ok, "235" <> _} -> :ok
      {:ok, line} -> {:error, line}
      err -> err
    end
  end

  defp speak_raw(socket, kind, data) do
    _ = send_raw(socket, kind, data)

    case recv_line(socket, kind) do
      {:ok, "250" <> _} -> :ok
      {:ok, line} -> {:error, line}
      err -> err
    end
  end

  defp maybe_auth(_socket, _kind, nil, _), do: :ok
  defp maybe_auth(_socket, _kind, "", _), do: :ok

  defp maybe_auth(socket, kind, user, pass) do
    with :ok <- speak(socket, kind, "AUTH LOGIN"),
         :ok <- speak(socket, kind, Base.encode64(to_string(user))),
         :ok <- speak(socket, kind, Base.encode64(to_string(pass))) do
      :ok
    end
  end

  defp rcpt_all(socket, kind, recipients) do
    Enum.reduce_while(recipients, :ok, fn rcpt, :ok ->
      case speak(socket, kind, "RCPT TO:<#{rcpt}>") do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp build_body(from, to_list, subject, html_body, cc, bcc) do
    to_hdr = Enum.join(to_list, ", ")
    cc_hdr = if cc, do: "Cc: #{Enum.join(List.wrap(cc), ", ")}\r\n", else: ""
    bcc_hdr = if bcc, do: "Bcc: #{Enum.join(List.wrap(bcc), ", ")}\r\n", else: ""

    """
    From: #{from}
    To: #{to_hdr}
    #{cc_hdr}#{bcc_hdr}Subject: #{subject}
    MIME-Version: 1.0
    Content-Type: text/html; charset=UTF-8

    #{html_body}
    """
    |> String.trim()
    |> String.replace("\n", "\r\n")
  end

  defp send_line(socket, :tcp, line), do: :gen_tcp.send(socket, line <> "\r\n")
  defp send_line(socket, :ssl, line), do: :ssl.send(socket, line <> "\r\n")

  defp send_raw(socket, :tcp, data), do: :gen_tcp.send(socket, data <> "\r\n")
  defp send_raw(socket, :ssl, data), do: :ssl.send(socket, data <> "\r\n")

  defp recv_line(socket, :tcp) do
    case :gen_tcp.recv(socket, 0, @timeout) do
      {:ok, bin} -> {:ok, String.trim(bin)}
      err -> err
    end
  end

  defp recv_line(socket, :ssl) do
    case :ssl.recv(socket, 0, @timeout) do
      {:ok, bin} -> {:ok, String.trim(bin)}
      err -> err
    end
  end

  defp close(socket, :tcp) do
    _ = :gen_tcp.close(socket)
    :ok
  end

  defp close(socket, :ssl) do
    _ = :ssl.close(socket)
    :ok
  end

  defp to_int(n) when is_integer(n), do: n

  defp to_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      _ -> 2525
    end
  end

  defp to_int(_), do: 2525
end
