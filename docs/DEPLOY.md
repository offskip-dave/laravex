# Production deployment

Laravex ships **zero runtime Hex dependencies**. HTTP, database, cache, queue, mail, and storage drivers use OTP stdlib plus optional host CLIs (`sqlite3`, `psql`, `mysql`, `redis-server` reachable via TCP, SMTP, S3-compatible HTTP).

## HTTP

- **Development:** `./artisan serve` (built-in listener, Laravel-style DX).
- **Production:** run the release behind **Bandit** or another Elixir HTTP server, terminated by nginx/Caddy/Traefik (TLS, HTTP/2, rate limits). `./artisan serve` is not intended for production traffic volumes.
- Terminate TLS at the reverse proxy; forward `X-Forwarded-*` headers and keep `TrustProxies` enabled in `bootstrap/app.ex`.

## Database

| `DB_CONNECTION` | Requirement |
|---|---|
| `sqlite` (default) | `sqlite3` CLI |
| `pgsql` / `postgres` | `psql` CLI + running PostgreSQL |
| `mysql` / `mariadb` | `mysql` CLI + running MySQL/MariaDB |

Set credentials in `.env` (`DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`).

## Redis (optional)

Set `CACHE_STORE=redis`, `SESSION_DRIVER=redis`, or `QUEUE_CONNECTION=redis` with `REDIS_HOST` / `REDIS_PORT`. Laravex speaks RESP over `:gen_tcp` (no `redix` Hex package).

## Mail

`MAIL_MAILER=smtp` uses the built-in SMTP transport (`MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`).

## Filesystems

`FILESYSTEM_DISK=s3` uses `:httpc` with optional AWS SigV4 when `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` are set; otherwise configure `AWS_ENDPOINT` for MinIO-style endpoints.

## Broadcasting

`BROADCAST_CONNECTION=pubsub` uses a local `Registry` for in-process fan-out (no Reverb/Pusher SaaS).

## Checklist

1. `mix compile` / release build in CI
2. Run migrations: `./artisan migrate --force`
3. `mix test` on the target branch
4. Configure process supervisor (systemd, Fly, etc.) for the OTP application + reverse proxy
5. Point health checks at `/up` or JSON `/health`
