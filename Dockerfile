# syntax=docker/dockerfile:1.7

FROM golang:1.23-alpine AS build
WORKDIR /src

RUN apk add --no-cache git

COPY go.mod go.sum* ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/api ./cmd/api

# --- migrate stage: bundle goose for the migrator service ---
FROM golang:1.23-alpine AS goose
RUN go install github.com/pressly/goose/v3/cmd/goose@v3.22.1

# --- final api image ---
FROM gcr.io/distroless/static-debian12:nonroot AS api
WORKDIR /app
COPY --from=build /out/api /app/api
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/api"]

# --- migrator image ---
FROM alpine:3.20 AS migrator
RUN apk add --no-cache ca-certificates
COPY --from=goose /go/bin/goose /usr/local/bin/goose
COPY migrations /migrations
WORKDIR /migrations
ENTRYPOINT ["sh", "-c", "goose -dir /migrations postgres \"$DATABASE_URL\" up"]
