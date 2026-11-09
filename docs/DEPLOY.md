# Production deployment

Laravex defaults to **zero-Hex drivers** (CLI DB, RESP `:gen_tcp`, SMTP, S3 `:httpc`). Optional **native Hex clients** activate when configured (`DB_CLIENT=native`, `REDIS_CLIENT=native`, etc.).

## HTTP

- **Development:** `./artisan serve` (built-in listener, Laravel-style DX).
- **Production:** run the release behind **Bandit** or another Elixir HTTP server, terminated by nginx/Caddy/Traefik (TLS, HTTP/2, rate limits). `./artisan serve` is not intended for production traffic volumes.
- Terminate TLS at the reverse proxy; forward `X-Forwarded-*` headers and keep `TrustProxies` enabled in `bootstrap/app.ex`.

## Database

| `DB_CONNECTION` | Default (`DB_CLIENT=cli`) | Native (`DB_CLIENT=native`) |
|---|---|---|
| `sqlite` | `sqlite3` CLI | Exqlite + DBConnection pool |
| `pgsql` / `postgres` | `psql` CLI | Postgrex pool |
| `mysql` / `mariadb` | `mysql` CLI | MyXQL pool |
| `sqlsrv` | not available | TDS pool |

Multi-connection: `Laravex.Database.Connection.using_connection/2`, query `connection/2`, model `connection/1`. Pool size: `DB_POOL_SIZE` / connection `pool` key.

## Redis

Default RESP over `:gen_tcp`. Set `REDIS_CLIENT=native` for Redix pools; `REDIS_TLS=true` for SSL. Best-effort cluster slot routing via `Laravex.Support.RedisCluster` (not Sentinel).

## Cache / session / queue

| Feature | Drivers |
|---|---|
| Cache | array · file · database · redis · **memcached** |
| Session | file · database · redis · **cookie** |
| Queue | sync · database · deferred · redis · **sqs** |

## Mail

`log` · `array` · `smtp` · **ses** · **postmark** · **resend** (`MAIL_MAILER=…`).

## Filesystems

`FILESYSTEM_DISK=s3` supports single PUT, multipart upload (>5MB), and ranged `stream_get/3`.

## Broadcasting

`BROADCAST_CONNECTION=pubsub` uses a local `Registry` for in-process fan-out (no Reverb/Pusher SaaS).

## Checklist

1. `mix compile --warnings-as-errors` / release build in CI
2. Run migrations: `./artisan migrate --force`
3. `mix test` on the target branch
4. Configure process supervisor (systemd, Fly, etc.) for the OTP application + reverse proxy
5. Point health checks at `/up` or JSON `/health`
6. For schedule/queue daemons: `./artisan schedule:work`, `./artisan queue:listen`
