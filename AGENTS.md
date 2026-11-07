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
- Models (Eloquex): prefer `use Laravex.Eloquex.Model, table: "…"`. Support `fillable`/`guarded`, `appends`, `touches`, `touch/1`, `refresh`/`increment`/`decrement`, relations (`has_many`/`has_one`/`belongs_to`/`belongs_to_many` + attach/detach/sync), `where_has`/`has`/`doesnt_have`, `load_missing`/`load_count`/`without`, `find_or_fail`/`first_or_fail`, `upsert`/`insert_or_ignore`, batched `with/2`, `with_count/2`, `paginate`/`simple_paginate`, `chunk`/`chunk_by_id`. Query: `join`/`left_join`, `group_by`/`having`/`select_raw`/`distinct`, `when_cond`/`unless_cond`, `latest`/`oldest`, `where_raw`/`or_where_raw`. Schema: `create`/`table`/`alter`/`rename`; Blueprint `soft_deletes`/`morphs`/`nullable_morphs`. Factories: `count/2`, `sequence/1`, `Laravex.Support.Faker`. `Laravex.Database.Model` is a compatibility alias. Feature tests: `Laravex.TestCase` (`get`/`post`/`json`, `acting_as`, `assert_redirected`/`assert_json`).
- Health: plain `/up` plus JSON `/health` (DB ping).
- Middleware: global stack (`TrustProxies`, `TrustHosts`, `HandleCors`, `TrimStrings`, `ConvertEmptyStringsToNull`) then `web` (session/CSRF) or `api` (`throttle:api`, no CSRF). Customize via `with_middleware` in `bootstrap/app.ex` (`prepend_to_group` / `append_to_group` / `prepend_global`). Aliases: `auth`, `guest`, `can:ability[,param]`, `ability:…` / `abilities:a,b`, `throttle:60,1` or `throttle:api`, `signed`, `cache.headers:public;max_age=60;etag`.
- CORS: `config/cors.exs` (loaded automatically). Artisan: `env`, `key:generate`, `about`, `down`/`up`, `route:cache`/`route:clear`, `optimize`/`optimize:clear`.
- Request helpers: `wants_json?/1`, `ajax?/1`, `accepts?/2`, `full_url/1`, `ip/1`, `secure?/1`, `only`/`except`/`keys`/`collect`, `has?`/`missing?`/`filled?`/`boolean`/`integer`/`float`/`date`/`string`/`enum`, `when_has`/`when_filled`, `merge`/`replace`/`merge_if_missing`. Filesystem disks: local driver only (non-local raises). Cache stores: `array`/`file`/`database` only.
- Blade `@json($var)`, `{!! !!}`, `@links($pager)`, `@isset`/`@empty`, `@once`, `@class([...])`, `@verbatim`, `@props([...])`, `@aware([...])`, `@includeIf`/`@includeWhen`/`@includeUnless`, `@can`/`@cannot`, `@pushOnce`/`@prepend`; Collection `take`/`skip`/`slice`/`nth`/`get`/`put`/`keys`/`flip`/`sort_keys`/`contains?`/`unique`/`merge`/`implode`/`shuffle`/`random`/`pad`/`cross_join`/`sliding`/`when_cond`; helpers `blank?`/`filled?`/`data_get`/`data_set`/`abort_if`; `cookie/3` / `cookie_forever/3` / `cookie_expire` via `AddQueuedCookies`.
- Sessions: `file`/`database` only (raises otherwise); flash bag + `flash.now` / `flash()` helpers; `get`/`put`/`pull`/`forget`/`all`/`only`/`keep`/`reflash`. FormRequest via `form_request:` with `messages/0`/`attributes/0`; `validated/0` returns only rule keys. Validation: `bail`, `json`/`ip`/`password`, `ascii`/`hex_color`/`ulid`/`mac_address`, `present_if`/`missing`/`missing_if`/`prohibits`, `required_array_keys`/`contains`/`doesnt_contain`, `required_with*`/`exclude_*`, nested `items.*.field`, `accepted`/`alpha*`/`gt`/`…`, date/file/numeric/url/uuid. Cache: `has?`/`add`/`pull`/`forever`/`remember_forever`/`increment`/`decrement`/`lock`/`get_lock`/`release`/`block`. Events: `until`/`dispatch_if`/`dispatch_unless`. Notifications: `later`/`notify_later`. Schema Blueprint emits `CREATE INDEX` for `index: true`. API tokens: abilities, `expires_at`/`last_used_at`, `revoke`/`prune_expired` (`sanctum:prune-expired`). Storage: visibility, `download`, `temporary_url`, `missing?`/`last_modified`, `put_file_as`/`all_files`, `directories`/`make_directory`/`mime_type`, `asset`/`storage_url`. Artisan: schedule/event/queue batch tools, `db:show`/`model:show`; `make:*` via Generators. Bus chain/batch. JsonResource `when_loaded`/`merge_when`/`additional`/`wrap`. Redirect: `with_input`/`with_errors`/`refresh`/`intended`/`redirect_intended`/`to_route`/`away`; Response `created`/`no_content`/`with_header`/`with_headers`. RateLimiter `attempt`/`hit`/`too_many_attempts?`/`clear`. Mail `cc`/`bcc`/`reply_to` + `assert_not_sent`. Arr (`add`/`undot`/`has_any?`/`first`/`last` callbacks) / Str (`after_value`/`headline`/`ulid`/`is_ulid?`/`is_mac_address?`/`is_uuid?`/`is_json?`/`is_ip?`) helpers. CookieJar `forever`/`expire`/`unqueue`/`forget`. Auth Guard `guest?`.
- Policies live in `app/Policies/*Policy.ex` and resolve via `Laravex.Auth.Gate` (`before`/`after_check`, `any?`/`none?`).
- Prefer extending `lib/laravex/*` for framework behavior; keep `app/` for application code.

## Out of scope (for now)

- Phoenix generators / LiveView / contexts as the app API
- Full driver matrix (mysql/pgsql, Redis, SMTP, Reverb, Horizon, …)
- Proof-of-fix test suites for work-in-progress features
