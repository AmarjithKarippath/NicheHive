-- +goose Up
-- +goose StatementBegin

CREATE TABLE users (
    id           BIGSERIAL PRIMARY KEY,
    google_id    TEXT NOT NULL UNIQUE,
    email        TEXT NOT NULL UNIQUE,
    username     TEXT NOT NULL UNIQUE,
    avatar_url   TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE communities (
    id           BIGSERIAL PRIMARY KEY,
    name         TEXT NOT NULL UNIQUE,
    description  TEXT NOT NULL DEFAULT '',
    creator_id   BIGINT NOT NULL REFERENCES users(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    search_tsv   TSVECTOR GENERATED ALWAYS AS (
        setweight(to_tsvector('english'::regconfig, name), 'A') ||
        setweight(to_tsvector('english'::regconfig, coalesce(description, '')), 'B')
    ) STORED
);

CREATE INDEX communities_search_idx ON communities USING GIN (search_tsv);
CREATE INDEX communities_name_lower_idx ON communities (LOWER(name));

CREATE TABLE memberships (
    community_id BIGINT NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
    user_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (community_id, user_id)
);

CREATE INDEX memberships_user_idx ON memberships (user_id);

CREATE TYPE post_kind AS ENUM ('text', 'link');

CREATE TABLE posts (
    id           BIGSERIAL PRIMARY KEY,
    community_id BIGINT NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
    author_id    BIGINT NOT NULL REFERENCES users(id),
    kind         post_kind NOT NULL,
    title        TEXT NOT NULL,
    body         TEXT,
    url          TEXT,
    ups          INTEGER NOT NULL DEFAULT 0,
    downs        INTEGER NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at   TIMESTAMPTZ,
    search_tsv   TSVECTOR GENERATED ALWAYS AS (
        setweight(to_tsvector('english'::regconfig, title), 'A') ||
        setweight(to_tsvector('english'::regconfig, coalesce(body, '')), 'B')
    ) STORED,
    CONSTRAINT post_body_or_url CHECK (
        (kind = 'text' AND body IS NOT NULL) OR
        (kind = 'link' AND url  IS NOT NULL)
    )
);

CREATE INDEX posts_community_created_idx ON posts (community_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX posts_created_idx           ON posts (created_at DESC)                WHERE deleted_at IS NULL;
CREATE INDEX posts_author_idx            ON posts (author_id, created_at DESC)    WHERE deleted_at IS NULL;
CREATE INDEX posts_search_idx            ON posts USING GIN (search_tsv);

-- Popular feed: compute hot score at query time.
--   ORDER BY (LOG(GREATEST(ABS(ups - downs), 1)) * SIGN(ups - downs)
--             + EXTRACT(EPOCH FROM created_at) / 45000.0) DESC

CREATE TABLE comments (
    id           BIGSERIAL PRIMARY KEY,
    post_id      BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    parent_id    BIGINT REFERENCES comments(id) ON DELETE CASCADE,
    author_id    BIGINT NOT NULL REFERENCES users(id),
    body         TEXT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at   TIMESTAMPTZ
);

CREATE INDEX comments_post_idx   ON comments (post_id, created_at);
CREATE INDEX comments_parent_idx ON comments (parent_id);
CREATE INDEX comments_author_idx ON comments (author_id, created_at DESC) WHERE deleted_at IS NULL;

CREATE TABLE post_votes (
    post_id    BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    value      SMALLINT NOT NULL CHECK (value IN (-1, 1)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);

CREATE INDEX post_votes_user_idx ON post_votes (user_id);

CREATE TABLE community_bans (
    community_id BIGINT NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
    user_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    banned_by    BIGINT NOT NULL REFERENCES users(id),
    reason       TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (community_id, user_id)
);

CREATE TABLE sessions (
    token       TEXT PRIMARY KEY,
    user_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ NOT NULL
);

CREATE INDEX sessions_user_idx ON sessions (user_id);
CREATE INDEX sessions_expires_idx ON sessions (expires_at);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS sessions;
DROP TABLE IF EXISTS community_bans;
DROP TABLE IF EXISTS post_votes;
DROP TABLE IF EXISTS comments;
DROP TABLE IF EXISTS posts;
DROP TYPE  IF EXISTS post_kind;
DROP TABLE IF EXISTS memberships;
DROP TABLE IF EXISTS communities;
DROP TABLE IF EXISTS users;
-- +goose StatementEnd
