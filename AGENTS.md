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
routes/        # web.ex, console.ex (+ api/auth after install:*)
storage/       # logs, sessions, cache, uploads
tests/         # Feature + Unit (Laravel tests/ layout)
artisan        # CLI → mix artisan
lib/laravex/   # Framework runtime (Illuminate analogue)
```

## Commands

```bash
mix compile
./artisan list
./artisan migrate
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

## Conventions

- Bootstrap via `Bootstrap.App.build() |> Laravex.Foundation.Application.create/1`.
- Routes register in `Routes.Web` / `Routes.Console`; optional `Routes.Api` / `Routes.Auth` after install.
- Config: `Laravex.Config.Repository.get("app.name")` — files under `config/*.exs` except Mix’s `config.exs` / `dev.exs` / `test.exs` / `prod.exs` / `runtime.exs`.
- Models: `use Laravex.Database.Model, table: "…"`.
- Middleware groups: `web` (session/CSRF) vs `api` (no CSRF).
- Prefer extending `lib/laravex/*` for framework behavior; keep `app/` for application code.

## Out of scope (for now)

- Phoenix generators / LiveView / contexts as the app API
- Full driver matrix (mysql/pgsql, Redis, SMTP, Reverb, Horizon, …)
- Proof-of-fix test suites for work-in-progress features
