# Laravex

Laravel 13 default application setup, ported to Elixir with a Laravel-faithful layout (no Phoenix conventions).

## Quick start

```bash
cp .env.example .env
mix compile
./artisan inspire
mix test
```

Serve HTTP:

```bash
elixir public/index.exs --serve
```

## Layout

Mirrors `laravel/laravel` 13.x: `app/`, `bootstrap/`, `config/`, `database/`, `public/`, `resources/`, `routes/`, `storage/`, `tests/`, plus `artisan`.
