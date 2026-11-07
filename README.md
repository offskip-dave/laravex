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
| Auth web loop | Session, CSRF, flash, session guard, policies/gates, validation (unique/exists + redirect), hashing, Crypt, signed URLs, DB API tokens |
| DX | `make:*`, migrate/fresh/wipe/seed, route:list, serve, tinker REPL, EventServiceProvider, `AGENTS.md` |
| Services | Cache, database queue worker, mail (log/array), filesystem disks (`store`/`url`), `storage:link` |
| HTTP | Static files, multipart uploads, JsonResource + paginated JSON, OTP `:json` |
| Views | Blade-like `{{ }}`, `old()`, `@csrf`, `@method`, `@vite`, `@if`/`@else`/`@unless`, `@include`, `@foreach`, `@error`, `@session`, `@auth`/`@guest`/`@can`, `@component`/`@slot`, `@push`/`@stack`, layouts |
| Async | Events/listeners, notifications, schedule (cron/`hourly`/`daily`), broadcasting bus |
| Ecosystem | `install:api` (tokens), `install:broadcasting`, `install:starter-kit`, observability recorder |

## Layout

Mirrors `laravel/laravel` 13.x: `app/`, `bootstrap/`, `config/`, `database/`, `public/`, `resources/`, `routes/`, `storage/`, `tests/`, `artisan`. Runtime lives under `lib/laravex/`.
