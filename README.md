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
| Foundation | Container, HTTP/router (params, groups, resources), middleware (session/CSRF/bindings), exceptions, logging |
| Database | SQLite via `sqlite3` CLI, Schema/Blueprint, dynamic migrations, query builder, Eloquent (relations, pagination, soft deletes) |
| Auth web loop | Session, CSRF, session guard, validation / form requests, hashing, Crypt |
| DX | `make:*` (real table names), migrate/seed, route:list, serve, tinker REPL, `AGENTS.md` |
| Services | Cache, database queue worker, mail (log/array), filesystem disks, `storage:link` |
| HTTP | Static files from `public/`, OTP `:json` |
| Views | Blade-like `{{ }}`, `@csrf`, `@vite`, `@if`, `@foreach`, `@error`, `@component`/`@slot`, `@push`/`@stack`, layouts |
| Async | Events/listeners, notifications, schedule (cron/`hourly`/`daily`), broadcasting bus |
| Ecosystem | `install:api` (tokens), `install:broadcasting`, `install:starter-kit`, observability recorder |

## Layout

Mirrors `laravel/laravel` 13.x: `app/`, `bootstrap/`, `config/`, `database/`, `public/`, `resources/`, `routes/`, `storage/`, `tests/`, `artisan`. Runtime lives under `lib/laravex/`.
