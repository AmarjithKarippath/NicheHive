-- +goose Up
-- +goose StatementBegin

CREATE TYPE feedback_kind AS ENUM ('bug', 'enhancement', 'other');

CREATE TABLE feedback (
    id         BIGSERIAL PRIMARY KEY,
    user_id    BIGINT REFERENCES users(id) ON DELETE SET NULL,
    kind       feedback_kind NOT NULL,
    message    TEXT NOT NULL,
    user_agent TEXT,
    page_url   TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX feedback_created_idx ON feedback (created_at DESC);
CREATE INDEX feedback_kind_idx    ON feedback (kind, created_at DESC);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS feedback;
DROP TYPE  IF EXISTS feedback_kind;
-- +goose StatementEnd
