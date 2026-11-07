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
| Database | SQLite, Schema/Blueprint (`soft_deletes`/`morphs`, `table`/`alter`), migrations, query builder (`join`/`right_join`/`add_select`/`or_where_column`/`or_where_between`/`or_where_date`/`or_having`/`when_cond`/`latest`/`upsert`), **Eloquex** (relations, `where_has`/`or_where_doesnt_have`/`has`/`trashed?`/`load_missing`/`load_count`/`without`, `find_or_fail`, `with`/`with_count`, paginate/chunk, scopes, factories + Faker) |
| Auth web loop | Session (file/database), CSRF, flash, guard, policies/gates (`before`/`after_check`/`define`/`forget`/`undefine`), password broker/reset, `verified`/`password.confirm` middleware, FormRequest (`messages`/`attributes`, nested/conditional/`accepted`/`alpha*`/`gt` rules, filtered `validated`), Crypt, signed URLs, API tokens (abilities, expiry, revoke/prune) |
| DX | `make:*`, migrate/fresh/wipe/seed, config/route/event/view cache, `optimize`, `db:show`/`model:show`, queue failed + batch tools, schedule (`withoutOverlapping`)/event list, serve, tinker, Str (`excerpt`)/Arr/Collection (`sole`/`intersect`)/`blank?`/`throw_if`/`data_get`, CookieJar `get`, feature `TestCase` helpers, `AGENTS.md` |
| Services | Cache (`increment`/`lock`/`remember_forever`/`add`/`pull`/`many`), queue (sync/database/deferred, ShouldQueue, tries/backoff, failed retry), Bus chain + batch (cancel/list), queued listeners, mail (log/array, fluent cc/bcc/reply_to/attach/attach_data), notifications (`later`/inbox/`mark_as_unread`), logging, filesystem (visibility/download/`response`/`temporary_url`/`append`/`prepend`/`all_files`/`all_directories`/`mime_type`), RateLimiter `attempt`/`hit` |
| HTTP | Static files, multipart uploads + mimes validation, downloads, JsonResource (`merge_when`/`additional`/`wrap`) + paginator `links`, OTP `:json`, `Http.Client` (fluent + fake/stub/assert) |
| Views | Blade `{{ }}`/`{!! !!}`, `View.share`, `old()`, `@lang`/`__()`, `@csrf`/`@method`/`@selected`/`@checked`/`@disabled`/`@readonly`/`@required`/`@switch`/`@class`/`@isset`/`@once`/`@verbatim`/`@props`/`@aware`/`@links`/`@pushOnce`/`@prependOnce`, `@if`/`@forelse`, `@include`/`@includeIf`/`@includeWhen`/`@includeUnless`, `@foreach`, `@error`/`@session`, `@auth`/`@can`/`@cannot`, `@json`, components/stacks |
| Async | Events (`until`/`dispatch_if`)/listeners, notifications (`later`), schedule (cron/`hourly`/`daily`), broadcasting bus + channel auth |
| Ecosystem | `install:api` (tokens), `install:broadcasting`, `install:starter-kit`, observability recorder |

## Layout

Mirrors `laravel/laravel` 13.x: `app/`, `bootstrap/`, `config/`, `database/`, `public/`, `resources/`, `routes/`, `storage/`, `tests/`, `artisan`. Runtime lives under `lib/laravex/`.
