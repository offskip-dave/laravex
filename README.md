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
| Foundation | Container, HTTP/router (params, groups, resources/apiResource), middleware (session/CSRF/bindings/auth/guest/can/throttle/signed), exceptions, logging |
| Database | SQLite via `sqlite3` CLI, Schema/Blueprint, dynamic migrations, query builder, Eloquent (relations, pagination, soft deletes, scopes, dirty tracking) |
| Auth web loop | Session, CSRF, flash, guard, policies/gates, password broker/reset, validation depth, Crypt, signed URLs, DB API tokens |
| DX | `make:*`, migrate/fresh/wipe/seed, route:list, serve, tinker, EventServiceProvider, Collection helpers, `AGENTS.md` |
| Services | Cache, queue, mail (views/from/fake), notifications (Notifiable), logging (levels/daily/placeholders), filesystem |
| HTTP | Static files, multipart uploads, JsonResource + paginator links, OTP `:json` |
| Views | Blade `{{ }}`, `old()`, `@csrf`/`@method`, `@if`/`@else`/`@unless`/`@forelse`, `@include`, `@foreach`, `@error`/`@session`, `@auth`/`@can`, components/stacks |
| Async | Events/listeners, notifications, schedule (cron/`hourly`/`daily`), broadcasting bus |
| Ecosystem | `install:api` (tokens), `install:broadcasting`, `install:starter-kit`, observability recorder |

## Layout

Mirrors `laravel/laravel` 13.x: `app/`, `bootstrap/`, `config/`, `database/`, `public/`, `resources/`, `routes/`, `storage/`, `tests/`, `artisan`. Runtime lives under `lib/laravex/`.
