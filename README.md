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
| Database | SQLite, Schema/Blueprint, migrations, query builder, **Eloquex** (fillable/guarded, touch/refresh/increment, relations, `with`/`with_count`, paginate/chunk, scopes, factories + Faker) |
| Auth web loop | Session (file/database), CSRF, flash, guard, policies/gates, password broker/reset, FormRequest (`messages`/`attributes`, filtered `validated`), Rule + file/date rules, Crypt, signed URLs, API tokens with abilities |
| DX | `make:*`, migrate/fresh/wipe/seed, config/route/event/view cache, `optimize`, `db:show`/`model:show`, queue failed + batch tools, schedule (`withoutOverlapping`)/event list, serve, tinker, Str/Arr, Collection, `AGENTS.md` |
| Services | Cache, queue (sync/database/deferred, ShouldQueue, tries/backoff, failed retry), Bus chain + batch (cancel/list), queued listeners, mail (log/array), notifications inbox, logging, filesystem (visibility/download), named rate limiters |
| HTTP | Static files, multipart uploads + mimes validation, downloads, JsonResource (`merge_when`/`additional`/`wrap`) + paginator `links`, OTP `:json`, `Http.Client` (fluent + fake/stub/assert) |
| Views | Blade `{{ }}`/`{!! !!}`, `old()`, `@lang`/`__()`, `@csrf`/`@method`/`@selected`/`@checked`/`@class`/`@isset`/`@once`/`@verbatim`/`@links`/`@pushOnce`, `@if`/`@forelse`, `@include`, `@foreach`, `@error`/`@session`, `@auth`/`@can`, `@json`, components/stacks |
| Async | Events/listeners, notifications, schedule (cron/`hourly`/`daily`), broadcasting bus + channel auth |
| Ecosystem | `install:api` (tokens), `install:broadcasting`, `install:starter-kit`, observability recorder |

## Layout

Mirrors `laravel/laravel` 13.x: `app/`, `bootstrap/`, `config/`, `database/`, `public/`, `resources/`, `routes/`, `storage/`, `tests/`, `artisan`. Runtime lives under `lib/laravex/`.
