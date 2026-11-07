# Laravex

Laravel 13 default application setup and Illuminate-shaped runtime, ported to Elixir with a **Laravel-faithful** layout (no Phoenix conventions).

## Quick start

```bash
cp .env.example .env
mix compile
./artisan migrate
./artisan db:seed
./artisan serve
./artisan inspire
mix test
```

## Artisan

```bash
./artisan list
./artisan make:model Post -m
./artisan route:list
./artisan queue:work --once
./artisan schedule:run
./artisan install:api
./artisan install:broadcasting
./artisan install:starter-kit
./artisan tinker
```

## What’s included

| Layer | Capabilities |
|---|---|
| Foundation | Container, HTTP/router, global + terminable middleware, CORS, TrustHosts/Proxies, cache.headers, cookie encrypt, `/up` + `/health`, JSON 404/exceptions, logging |
| Database | SQLite, Schema/Blueprint, migrations, query builder, **Eloquex** (fillable/guarded, touch, relations, scopes, factories) |
| Auth web loop | Session (file/database), CSRF, flash, guard, policies/gates, password broker/reset, FormRequest + Rule objects, Crypt, signed URLs, DB API tokens |
| DX | `make:*`, migrate/fresh/wipe/seed, config/route/view cache, `optimize`, route:list, serve, tinker, `env`/`key:generate`/`about`/`down`/`up`, Str/Arr, Collection, `AGENTS.md` |
| Services | Cache, queue (sync/database/deferred, ShouldQueue), mail, notifications, logging, filesystem, named rate limiters |
| HTTP | Static files, multipart uploads, JsonResource + paginator links, OTP `:json`, `Http.Client` outbound |
| Views | Blade `{{ }}`, `old()`, `@lang`/`__()`, `@csrf`/`@method`, `@if`/`@else`/`@unless`/`@forelse`, `@include`, `@foreach`, `@error`/`@session`, `@auth`/`@can`, components/stacks |
| Async | Events/listeners, notifications, schedule (cron/`hourly`/`daily`), broadcasting bus |
| Ecosystem | `install:api` (tokens), `install:broadcasting`, `install:starter-kit`, observability recorder |

## Layout

Mirrors `laravel/laravel` 13.x: `app/`, `bootstrap/`, `config/`, `database/`, `public/`, `resources/`, `routes/`, `storage/`, `tests/`, `artisan`. Runtime lives under `lib/laravex/`.
