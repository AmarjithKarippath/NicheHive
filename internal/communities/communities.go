package communities

import (
	"context"
	"errors"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/amar/reddit/internal/auth"
	"github.com/amar/reddit/internal/httpx"
)

var nameRe = regexp.MustCompile(`^[a-zA-Z0-9_]{3,24}$`)

type Community struct {
	ID          int64     `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	CreatorID   int64     `json:"creator_id"`
	CreatedAt   time.Time `json:"created_at"`
	MemberCount int64     `json:"member_count"`
	IsMember    bool      `json:"is_member"`
}

type Handler struct {
	pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Handler {
	return &Handler{pool: pool}
}

type createReq struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.FromContext(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req createReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	req.Description = strings.TrimSpace(req.Description)
	if !nameRe.MatchString(req.Name) {
		httpx.Error(w, http.StatusBadRequest, "name must be 3-24 chars, [a-zA-Z0-9_]")
		return
	}
	if len(req.Description) > 500 {
		httpx.Error(w, http.StatusBadRequest, "description too long (max 500)")
		return
	}

	tx, err := h.pool.Begin(r.Context())
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	defer tx.Rollback(r.Context())

	var c Community
	err = tx.QueryRow(r.Context(), `
		INSERT INTO communities (name, description, creator_id)
		VALUES ($1, $2, $3)
		RETURNING id, name, description, creator_id, created_at
	`, req.Name, req.Description, user.ID).
		Scan(&c.ID, &c.Name, &c.Description, &c.CreatorID, &c.CreatedAt)
	if err != nil {
		var pg *pgconn.PgError
		if errors.As(err, &pg) && pg.Code == "23505" {
			httpx.Error(w, http.StatusConflict, "name already taken")
			return
		}
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}

	if _, err := tx.Exec(r.Context(), `
		INSERT INTO memberships (community_id, user_id) VALUES ($1, $2)
	`, c.ID, user.ID); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}

	c.MemberCount = 1
	c.IsMember = true
	httpx.WriteJSON(w, http.StatusCreated, c)
}

func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	name := chi.URLParam(r, "name")
	userID := currentUserID(r)

	var c Community
	err := h.pool.QueryRow(r.Context(), `
		SELECT c.id, c.name, c.description, c.creator_id, c.created_at,
		       (SELECT COUNT(*) FROM memberships m WHERE m.community_id = c.id) AS member_count,
		       EXISTS(SELECT 1 FROM memberships m WHERE m.community_id = c.id AND m.user_id = $2) AS is_member
		FROM communities c
		WHERE LOWER(c.name) = LOWER($1)
	`, name, userID).
		Scan(&c.ID, &c.Name, &c.Description, &c.CreatorID, &c.CreatedAt, &c.MemberCount, &c.IsMember)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "community not found")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, c)
}

func (h *Handler) Join(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.FromContext(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	id, err := h.communityIDByName(r.Context(), chi.URLParam(r, "name"))
	if err != nil {
		writeLookupErr(w, err)
		return
	}
	// block banned users from rejoining
	var banned bool
	if err := h.pool.QueryRow(r.Context(),
		`SELECT EXISTS(SELECT 1 FROM community_bans WHERE community_id = $1 AND user_id = $2)`,
		id, user.ID,
	).Scan(&banned); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	if banned {
		httpx.Error(w, http.StatusForbidden, "you are banned from this community")
		return
	}
	if _, err := h.pool.Exec(r.Context(), `
		INSERT INTO memberships (community_id, user_id) VALUES ($1, $2)
		ON CONFLICT DO NOTHING
	`, id, user.ID); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) Leave(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.FromContext(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	id, err := h.communityIDByName(r.Context(), chi.URLParam(r, "name"))
	if err != nil {
		writeLookupErr(w, err)
		return
	}
	if _, err := h.pool.Exec(r.Context(),
		`DELETE FROM memberships WHERE community_id = $1 AND user_id = $2`,
		id, user.ID,
	); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) communityIDByName(ctx context.Context, name string) (int64, error) {
	var id int64
	err := h.pool.QueryRow(ctx, `SELECT id FROM communities WHERE LOWER(name) = LOWER($1)`, name).Scan(&id)
	return id, err
}

func writeLookupErr(w http.ResponseWriter, err error) {
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "community not found")
		return
	}
	httpx.Error(w, http.StatusInternalServerError, "db error")
}

// currentUserID returns the authenticated user's id, or 0 if anonymous.
// 0 never matches a real user id, so EXISTS / membership lookups are safe.
func currentUserID(r *http.Request) int64 {
	if u, ok := auth.FromContext(r.Context()); ok {
		return u.ID
	}
	return 0
}
