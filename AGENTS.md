# Laravex — Agent / contributor notes

Laravex is a **Laravel-faithful** Elixir port of the Laravel 13 application skeleton plus a thin Illuminate-shaped runtime. Do **not** introduce Phoenix directory conventions (`lib/my_app_web`, contexts-as-primary UX, `router.ex` as the public app shape).

## Layout (public)

```
app/           # Application code (Models, Http, Providers, …)
bootstrap/     # Application builder + providers list
config/        # Laravel-style *.exs maps (not Mix env files)
database/      # migrations, factories, seeders
public/        # HTTP entry + static assets
resources/     # views, css, js
routes/        # web.ex, console.ex only by default
storage/       # logs, sessions, cache, uploads
tests/         # Feature + Unit (Laravel tests/ layout)
artisan        # CLI → mix artisan
lib/laravex/   # Framework runtime (Illuminate analogue)
```

Optional installables (`./artisan install:api|broadcasting|starter-kit`) add
`routes/api.ex`, `routes/auth.ex`, `config/broadcasting.exs`, auth views, etc.
Do not commit those into the default tree unless the install step is intentional.

## Commands

```bash
mix compile
./artisan list
./artisan migrate
./artisan migrate:fresh
./artisan db:wipe
./artisan db:seed
./artisan serve
./artisan make:model Post -m
./artisan route:list
./artisan tinker
./artisan queue:work --once
./artisan schedule:run
./artisan install:api|broadcasting|starter-kit
mix test
```

Password resets use `Laravex.Auth.Password` + `password_reset_tokens` (wired by `install:starter-kit`).


## Conventions

- Bootstrap via `Bootstrap.App.build() |> Laravex.Foundation.Application.create/1`.
- Routes register in `Routes.Web` / `Routes.Console`; optional `Routes.Api` / `Routes.Auth` after install.
- Config: `Laravex.Config.Repository.get("app.name")` — files under `config/*.exs` except Mix’s `config.exs` / `dev.exs` / `test.exs` / `prod.exs` / `runtime.exs`.
- Models (Eloquex): prefer `use Laravex.Eloquex.Model, table: "…"`. Support `fillable`/`guarded`, `appends`, `touches`, `touch/1`, `refresh`/`increment`/`decrement`, relations (`has_many`/`has_one`/`belongs_to`/`belongs_to_many` + attach/detach/sync), batched `with/2`, `with_count/2`. `Laravex.Database.Model` is a compatibility alias.
- Health: plain `/up` plus JSON `/health` (DB ping).
- Middleware: global stack (`TrustProxies`, `TrustHosts`, `HandleCors`, `TrimStrings`, `ConvertEmptyStringsToNull`) then `web` (session/CSRF) or `api` (`throttle:api`, no CSRF). Customize via `with_middleware` in `bootstrap/app.ex` (`prepend_to_group` / `append_to_group` / `prepend_global`). Aliases: `auth`, `guest`, `can:ability[,param]`, `ability:…` / `abilities:a,b`, `throttle:60,1` or `throttle:api`, `signed`, `cache.headers:public;max_age=60;etag`.
- CORS: `config/cors.exs` (loaded automatically). Artisan: `env`, `key:generate`, `about`, `down`/`up`, `route:cache`/`route:clear`, `optimize`/`optimize:clear`.
- Request helpers: `wants_json?/1`, `ajax?/1`, `accepts?/2`, `full_url/1`, `ip/1`, `secure?/1`. Filesystem disks: local driver only (non-local raises). Cache stores: `array`/`file`/`database` only.
- Blade `@json($var)`, `@isset`/`@empty`, `@once`, `@class([...])`, `@verbatim`; Collection `sort_by`/`first_where`/`flat_map`; `cookie/3` queues via `AddQueuedCookies`.
- Sessions: `file`/`database` only (raises otherwise); flash bag + `flash.now` / `flash()` helpers. FormRequest via `form_request:`; `validated/0`. Validation: `required_if`/`required_unless`/`prohibited`/`sometimes`/`date`/`date_format`. Artisan: `schedule:list`, `event:list`/`event:cache`, `queue:failed`/`retry`, `db:show`, `model:show`; `make:*` via `Laravex.Generators`. Queue connections: `sync`/`database`/`deferred` (job `tries`/`backoff` release before `failed_jobs`). Bus: `chain` + `batch`. Queued listeners via `use Laravex.Events.ShouldQueue`. Schedule `without_overlapping: true`. Broadcast: `log`/`null`/`array` + `Broadcasting.Channel` auth (`routes/channels.ex`). Notifications DB inbox (`notifications` table + `unread_notifications`/`mark_*_as_read`). API tokens: abilities + `token_can?` / `ability:` middleware. `Http.Client` fake/stub/assert + `with_headers`/`accept_json`. JsonResource `when_loaded`/`merge`. Blade `@selected`/`@checked`. Arr: `pull`/`dot`/`collapse`/`where`; Str: `squish`/`uuid`/`replace`/`mask`.
- Policies live in `app/Policies/*Policy.ex` and resolve via `Laravex.Auth.Gate`.
- Prefer extending `lib/laravex/*` for framework behavior; keep `app/` for application code.

## Out of scope (for now)

- Phoenix generators / LiveView / contexts as the app API
- Full driver matrix (mysql/pgsql, Redis, SMTP, Reverb, Horizon, …)
- Proof-of-fix test suites for work-in-progress features
