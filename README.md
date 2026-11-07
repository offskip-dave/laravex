<p align="center">
  <a href="https://github.com/offskip-dave/laravex" target="_blank">
    <img src="art/logo.svg" width="320" alt="Laravex Logo">
  </a>
</p>

<p align="center">
  <a href="https://github.com/offskip-dave/laravex/wiki"><img src="https://img.shields.io/badge/docs-wiki-blue" alt="Documentation"></a>
  <a href="https://elixir-lang.org"><img src="https://img.shields.io/badge/elixir-~%3E%201.17-4B275F" alt="Elixir"></a>
  <a href="https://github.com/offskip-dave/laravex/wiki/Limitations"><img src="https://img.shields.io/badge/status-early-orange" alt="Status"></a>
</p>

## About Laravex

Laravex is a web application skeleton and thin Illuminate-shaped runtime for Elixir. It brings Laravel’s expressive, enjoyable developer experience to the BEAM — same layout, familiar APIs, OTP underneath.

Laravex eases common tasks used in many web projects, such as:

- Simple, fast [routing](https://github.com/offskip-dave/laravex/wiki/Routing) and middleware groups.
- A powerful [service container](https://github.com/offskip-dave/laravex/wiki/Service-Container) and providers.
- Multiple back-ends for [session](https://github.com/offskip-dave/laravex/wiki/Session) and [cache](https://github.com/offskip-dave/laravex/wiki/Cache) storage.
- Expressive, intuitive [Eloquex](https://github.com/offskip-dave/laravex/wiki/Eloquex) ORM.
- Database-agnostic [schema migrations](https://github.com/offskip-dave/laravex/wiki/Migrations).
- Robust background [job processing](https://github.com/offskip-dave/laravex/wiki/Queues).
- Real-time [event broadcasting](https://github.com/offskip-dave/laravex/wiki/Broadcasting).

> **Elixir, not PHP. Laravel conventions, not Phoenix conventions.**  
> No `lib/my_app_web`, no contexts-as-primary UX, no LiveView as the default shape. If you know Laravel, Laravex feels familiar from day one.

## Learning Laravex

The [project wiki](https://github.com/offskip-dave/laravex/wiki) is the documentation home — installation, the request lifecycle, Eloquex, Blade, Artisan, and more. Agent/contributor notes live in [`AGENTS.md`](AGENTS.md). Deployment notes are in [`docs/DEPLOY.md`](docs/DEPLOY.md).

If you already know Laravel, start with [Directory Structure](https://github.com/offskip-dave/laravex/wiki/Directory-Structure) and [Limitations](https://github.com/offskip-dave/laravex/wiki/Limitations) so expectations stay honest.

## Quick start

```bash
cp .env.example .env
mix compile
./artisan key:generate
./artisan migrate
./artisan db:seed
./artisan serve
mix test
```

Your application will be available at `http://localhost:8000`. Use a reverse proxy + Bandit (or another Elixir HTTP server) in production; keep `./artisan serve` for local development.

## Artisan

```bash
./artisan list
./artisan make:model Post -m
./artisan make:resource UserCollection --collection
./artisan route:list
./artisan queue:work --once
./artisan schedule:run
./artisan install:api
./artisan install:broadcasting
./artisan install:starter-kit
./artisan tinker
```

## Layout

Mirrors `laravel/laravel` 13.x: `app/`, `bootstrap/`, `config/`, `database/`, `public/`, `resources/`, `routes/`, `storage/`, `tests/`, `artisan`. Runtime lives under `lib/laravex/`.

## FAQ

**What’s wrong with PHP?**  
Nothing. Laravel on PHP is excellent. Laravex isn’t a rejection of PHP — it’s for teams that want Laravel’s application shape and DX on the BEAM (OTP, concurrency, supervision, long-lived processes).

**Why not just use Phoenix?**  
Phoenix is the right default for most Elixir web apps. Laravex exists for a different bet: keep the Laravel mental model (`app/`, `routes/`, `artisan`, Eloquent-shaped models, Blade, middleware groups) instead of adopting Phoenix contexts, `*_web`, and LiveView as the primary UX. If you want idiomatic Elixir/Phoenix, use Phoenix.

**What’s the intention of Laravex?**  
Port the Laravel 13 application skeleton plus a thin Illuminate-shaped runtime to Elixir — faithful layout and APIs, not a line-by-line clone of every package. Prefer extending `lib/laravex/` for framework behavior and `app/` for application code. Stay zero-Hex where possible (CLI DB adapters, RESP Redis, SMTP, S3 via `:httpc`).

**Is it a drop-in Laravel replacement?**  
No. APIs aim to feel familiar so Laravel muscle memory transfers, but this is Elixir: immutability, pattern matching, and OTP replace PHP’s request lifecycle and some Illuminate internals. Expect gaps; see the [Limitations](https://github.com/offskip-dave/laravex/wiki/Limitations) wiki page and `AGENTS.md`.

**Who is this for?**  
Laravel developers curious about Elixir who don’t want to relearn an entire web stack on day one, and Elixir developers who prefer Laravel’s request/controller/resource style over Phoenix’s conventions.

## Contributing

Issues and pull requests are welcome. Prefer Laravel-faithful APIs and layout; do not introduce Phoenix directory conventions. See [`AGENTS.md`](AGENTS.md) for conventions and out-of-scope items.

## License

Laravex is open-source software. Not affiliated with Laravel LLC or the Elixir core team — built to feel like Laravel on the BEAM.
