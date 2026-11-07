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
| Database | SQLite (+ optional `psql`/`mysql` CLIs), Schema/Blueprint (`soft_deletes`/`morphs`, `table`/`alter`), migrations, query builder (`join`/`right_join`/`add_select`/`or_where_column`/`or_where_between`/`or_where_date`/`or_having`/`when_cond`/`latest`/`upsert`), **Eloquex** (relations, `where_has`/`or_where_doesnt_have`/`has`/`trashed?`/`load_missing`/`load_count`/`without`, `find_or_fail`, `with`/`with_count`, paginate/chunk, scopes, factories + Faker) |
| Auth web loop | Session (file/database), CSRF, flash, guard, policies/gates (`before`/`after_check`/`define`/`forget`/`undefine`), password broker/reset, `verified`/`password.confirm` middleware, FormRequest (`messages`/`attributes`, nested/conditional/`accepted`/`alpha*`/`gt` rules, filtered `validated`), Crypt, signed URLs, API tokens (abilities, expiry, revoke/prune) |
| DX | `make:*`, migrate/fresh/wipe/seed, config/route/event/view cache, `optimize`, `db:show`/`model:show`, queue failed + batch tools, schedule (`withoutOverlapping`)/event list, serve, tinker, Str (`excerpt`)/Arr/Collection (`sole`/`intersect`)/`blank?`/`throw_if`/`data_get`, CookieJar `get`, feature `TestCase` helpers, `AGENTS.md` |
| Services | Cache (`increment`/`lock`/`remember_forever`/`add`/`pull`/`many`; array/file/database/**redis**), queue (sync/database/deferred/**redis**), Bus chain + batch (cancel/list), queued listeners, mail (log/array/**smtp**), notifications (`later`/inbox/`mark_as_unread`), logging, filesystem (local/**s3**, visibility/download/`response`/`temporary_url`/…), RateLimiter `attempt`/`hit` |
| HTTP | Static files, multipart uploads + mimes validation, downloads, JsonResource (`when_loaded`/`when_cond`/`merge_when`/`additional`/`wrap`) + ResourceCollection (`collects`, paginator links/meta), OTP `:json`, `Http.Client` (fluent + fake/stub/assert) |
| Views | Blade `{{ }}`/`{!! !!}`, `View.share`, `old()`, `@lang`/`__()`, `@csrf`/`@method`/`@selected`/`@checked`/`@disabled`/`@readonly`/`@required`/`@switch`/`@class`/`@isset`/`@once`/`@verbatim`/`@props`/`@aware`/`@links`/`@pushOnce`/`@prependOnce`, `@if`/`@forelse`, `@include`/`@includeIf`/`@includeWhen`/`@includeUnless`, `@foreach`, `@error`/`@session`, `@auth`/`@can`/`@cannot`, `@json`, components/stacks |
| Async | Events (`until`/`dispatch_if`)/listeners, notifications (`later`), schedule (cron/`hourly`/`daily`), broadcasting bus + channel auth |
| Ecosystem | `install:api` (tokens), `install:broadcasting`, `install:starter-kit`, observability recorder |

## Layout

Mirrors `laravel/laravel` 13.x: `app/`, `bootstrap/`, `config/`, `database/`, `public/`, `resources/`, `routes/`, `storage/`, `tests/`, `artisan`. Runtime lives under `lib/laravex/`.

## Production HTTP

Use a reverse proxy + Bandit (or another Elixir HTTP server) for production; keep `./artisan serve` for local development. See [docs/DEPLOY.md](docs/DEPLOY.md).

## FAQ

**What’s wrong with PHP?**  
Nothing. Laravel on PHP is excellent. Laravex isn’t a rejection of PHP — it’s for teams that want Laravel’s application shape and DX on the BEAM (OTP, concurrency, supervision, long-lived processes).

**Why not just use Phoenix?**  
Phoenix is the right default for most Elixir web apps. Laravex exists for a different bet: keep the Laravel mental model (`app/`, `routes/`, `artisan`, Eloquent-shaped models, Blade, middleware groups) instead of adopting Phoenix contexts, `*_web`, and LiveView as the primary UX. If you want idiomatic Elixir/Phoenix, use Phoenix.

**What’s the intention of Laravex?**  
Port the Laravel 13 application skeleton plus a thin Illuminate-shaped runtime to Elixir — faithful layout and APIs, not a line-by-line clone of every package. Prefer extending `lib/laravex/` for framework behavior and `app/` for application code. Stay zero-Hex where possible (CLI DB adapters, RESP Redis, SMTP, S3 via `:httpc`).

**Is it a drop-in Laravel replacement?**  
No. APIs aim to feel familiar so Laravel muscle memory transfers, but this is Elixir: immutability, pattern matching, and OTP replace PHP’s request lifecycle and some Illuminate internals. Expect gaps; see `AGENTS.md` for what’s in and out of scope.

**Who is this for?**  
Laravel developers curious about Elixir who don’t want to relearn an entire web stack on day one, and Elixir developers who prefer Laravel’s request/controller/resource style over Phoenix’s conventions.
