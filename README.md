# NicheHive

Reddit-like MVP. Go backend + Postgres. Frontend (Next.js) lives separately.

## Stack
- Go 1.23, chi router, pgx/v5
- PostgreSQL 15+
- goose for migrations
- Google OAuth for auth

## Layout
```
cmd/api/             entry point
internal/config/     env loading
internal/db/         pgx pool
internal/server/     chi router + handlers
migrations/          goose SQL migrations
```

## Run with Docker Compose (recommended)
```
cp .env.example .env       # fill in Google OAuth creds
make up                    # builds api+migrator, starts postgres, runs migrations, then api
curl localhost:8080/healthz
make logs                  # tail api logs
make down                  # stop
```
Services:
- `postgres` — Postgres 16 with a named volume `pgdata`.
- `migrate` — one-shot goose runner; `api` waits for it to complete.
- `api` — distroless Go binary on :8080.

## Setup (local Go)
1. `cp .env.example .env` and fill in Google OAuth creds + DATABASE_URL.
2. Install tools:
   ```
   go install github.com/pressly/goose/v3/cmd/goose@latest
   ```
3. Create the database, then run migrations:
   ```
   make migrate-up
   ```
4. Run the API:
   ```
   make run
   ```
5. Health check: `curl localhost:8080/healthz`

## API (v1, scaffold)
All routes under `/api/v1`. Handlers currently return 501 — to be implemented next.

- `GET  /auth/google/login`
- `GET  /auth/google/callback`
- `POST /auth/logout`
- `GET  /me`
- `POST /communities` · `GET /communities/{name}` · `POST /communities/{name}/join|leave`
- `POST /communities/{name}/posts` · `GET /communities/{name}/posts`
- `GET  /posts/{id}` · `DELETE /posts/{id}`
- `GET  /feeds/home` · `GET /feeds/popular`
- `POST /posts/{id}/comments` · `GET /posts/{id}/comments` · `DELETE /comments/{id}`
- `POST /posts/{id}/vote`  (body: `{"value": 1 | -1 | 0}`)
- `POST /communities/{name}/bans` · `DELETE /communities/{name}/bans/{username}`
- `GET  /users/{username}` · `GET /search?q=...`

## Schema
See [migrations/0001_init.sql](migrations/0001_init.sql). Highlights:
- `posts.hot_score` is a generated column (log score + time decay) with an index for Popular.
- `posts.search_tsv` + `communities.search_tsv` for Postgres full-text search.
- Soft-delete via `deleted_at` on posts and comments.
- `community_bans` keyed by `(community_id, user_id)`; creator-only enforcement at the handler layer.
