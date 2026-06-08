.PHONY: run build tidy migrate-up migrate-down migrate-status

run:
	go run ./cmd/api

build:
	go build -o bin/api ./cmd/api

tidy:
	go mod tidy

# requires: go install github.com/pressly/goose/v3/cmd/goose@latest
migrate-up:
	goose -dir migrations postgres "$$DATABASE_URL" up

migrate-down:
	goose -dir migrations postgres "$$DATABASE_URL" down

migrate-status:
	goose -dir migrations postgres "$$DATABASE_URL" status

# --- docker ---
.PHONY: up down logs rebuild
up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f api web

rebuild:
	docker compose build --no-cache
