package comments

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/amar/reddit/internal/auth"
	"github.com/amar/reddit/internal/httpx"
)

type Comment struct {
	ID         int64     `json:"id"`
	PostID     int64     `json:"post_id"`
	ParentID   *int64    `json:"parent_id,omitempty"`
	AuthorID   int64     `json:"author_id"`
	AuthorName string    `json:"author_name"`
	Body       string    `json:"body"`
	Deleted    bool      `json:"deleted"`
	CreatedAt  time.Time `json:"created_at"`
}

type Handler struct {
	pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Handler {
	return &Handler{pool: pool}
}

type createReq struct {
	Body     string `json:"body"`
	ParentID *int64 `json:"parent_id,omitempty"`
}

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.FromContext(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	postID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	var req createReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	req.Body = strings.TrimSpace(req.Body)
	if req.Body == "" || len(req.Body) > 10000 {
		httpx.Error(w, http.StatusBadRequest, "body must be 1-10000 chars")
		return
	}

	// Verify post exists and parent (if any) belongs to it.
	var communityID int64
	err = h.pool.QueryRow(r.Context(),
		`SELECT community_id FROM posts WHERE id = $1 AND deleted_at IS NULL`, postID,
	).Scan(&communityID)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "post not found")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}

	var banned bool
	if err := h.pool.QueryRow(r.Context(),
		`SELECT EXISTS(SELECT 1 FROM community_bans WHERE community_id = $1 AND user_id = $2)`,
		communityID, user.ID,
	).Scan(&banned); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	if banned {
		httpx.Error(w, http.StatusForbidden, "you are banned from this community")
		return
	}

	if req.ParentID != nil {
		var parentPostID int64
		err := h.pool.QueryRow(r.Context(),
			`SELECT post_id FROM comments WHERE id = $1`, *req.ParentID,
		).Scan(&parentPostID)
		if errors.Is(err, pgx.ErrNoRows) || (err == nil && parentPostID != postID) {
			httpx.Error(w, http.StatusBadRequest, "invalid parent_id")
			return
		}
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			httpx.Error(w, http.StatusInternalServerError, "db error")
			return
		}
	}

	var c Comment
	err = h.pool.QueryRow(r.Context(), `
		INSERT INTO comments (post_id, parent_id, author_id, body)
		VALUES ($1, $2, $3, $4)
		RETURNING id, post_id, parent_id, author_id, body, created_at
	`, postID, req.ParentID, user.ID, req.Body).
		Scan(&c.ID, &c.PostID, &c.ParentID, &c.AuthorID, &c.Body, &c.CreatedAt)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	c.AuthorName = user.Username
	httpx.WriteJSON(w, http.StatusCreated, c)
}

func (h *Handler) ListByPost(w http.ResponseWriter, r *http.Request) {
	postID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	rows, err := h.pool.Query(r.Context(), `
		SELECT c.id, c.post_id, c.parent_id, c.author_id, u.username, c.body,
		       (c.deleted_at IS NOT NULL) AS deleted, c.created_at
		FROM comments c JOIN users u ON u.id = c.author_id
		WHERE c.post_id = $1
		ORDER BY c.created_at ASC
	`, postID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	defer rows.Close()

	out := make([]Comment, 0, 64)
	for rows.Next() {
		var c Comment
		if err := rows.Scan(&c.ID, &c.PostID, &c.ParentID, &c.AuthorID, &c.AuthorName,
			&c.Body, &c.Deleted, &c.CreatedAt); err != nil {
			httpx.Error(w, http.StatusInternalServerError, "db error")
			return
		}
		if c.Deleted {
			c.Body = "[deleted]"
		}
		out = append(out, c)
	}
	if rows.Err() != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"comments": out})
}

func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.FromContext(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	var authorID, creatorID int64
	err = h.pool.QueryRow(r.Context(), `
		SELECT c.author_id, com.creator_id
		FROM comments c
		JOIN posts p ON p.id = c.post_id
		JOIN communities com ON com.id = p.community_id
		WHERE c.id = $1 AND c.deleted_at IS NULL
	`, id).Scan(&authorID, &creatorID)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "comment not found")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	if user.ID != authorID && user.ID != creatorID {
		httpx.Error(w, http.StatusForbidden, "not allowed")
		return
	}
	if _, err := h.pool.Exec(r.Context(),
		`UPDATE comments SET deleted_at = NOW() WHERE id = $1`, id,
	); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
