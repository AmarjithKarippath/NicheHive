package posts

import (
	"context"
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

type Post struct {
	ID            int64     `json:"id"`
	CommunityID   int64     `json:"community_id"`
	CommunityName string    `json:"community_name"`
	AuthorID      int64     `json:"author_id"`
	AuthorName    string    `json:"author_name"`
	Kind          string    `json:"kind"`
	Title         string    `json:"title"`
	Body          *string   `json:"body,omitempty"`
	URL           *string   `json:"url,omitempty"`
	Ups           int       `json:"ups"`
	Downs         int       `json:"downs"`
	Score         int       `json:"score"`
	CommentCount  int       `json:"comment_count"`
	UserVote      int       `json:"user_vote"`
	CreatedAt     time.Time `json:"created_at"`
}

type Handler struct {
	pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Handler {
	return &Handler{pool: pool}
}

const baseSelect = `
SELECT p.id, p.community_id, c.name AS community_name,
       p.author_id, u.username AS author_name,
       p.kind::text, p.title, p.body, p.url,
       p.ups, p.downs, (p.ups - p.downs) AS score,
       (SELECT COUNT(*) FROM comments cm WHERE cm.post_id = p.id AND cm.deleted_at IS NULL) AS comment_count,
       COALESCE((SELECT value FROM post_votes v WHERE v.post_id = p.id AND v.user_id = $1), 0) AS user_vote,
       p.created_at
FROM posts p
JOIN communities c ON c.id = p.community_id
JOIN users u       ON u.id = p.author_id
WHERE p.deleted_at IS NULL
`

func scanPost(row pgx.Row, p *Post) error {
	return row.Scan(
		&p.ID, &p.CommunityID, &p.CommunityName,
		&p.AuthorID, &p.AuthorName,
		&p.Kind, &p.Title, &p.Body, &p.URL,
		&p.Ups, &p.Downs, &p.Score,
		&p.CommentCount, &p.UserVote, &p.CreatedAt,
	)
}

type createReq struct {
	Kind  string `json:"kind"`
	Title string `json:"title"`
	Body  string `json:"body,omitempty"`
	URL   string `json:"url,omitempty"`
}

func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.FromContext(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	name := chi.URLParam(r, "name")

	var req createReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	req.Title = strings.TrimSpace(req.Title)
	req.Body = strings.TrimSpace(req.Body)
	req.URL = strings.TrimSpace(req.URL)

	if len(req.Title) < 1 || len(req.Title) > 300 {
		httpx.Error(w, http.StatusBadRequest, "title must be 1-300 chars")
		return
	}
	switch req.Kind {
	case "text":
		if req.Body == "" {
			httpx.Error(w, http.StatusBadRequest, "text post requires body")
			return
		}
		if len(req.Body) > 10000 {
			httpx.Error(w, http.StatusBadRequest, "body too long (max 10000)")
			return
		}
	case "link":
		if req.URL == "" {
			httpx.Error(w, http.StatusBadRequest, "link post requires url")
			return
		}
		if !strings.HasPrefix(req.URL, "http://") && !strings.HasPrefix(req.URL, "https://") {
			httpx.Error(w, http.StatusBadRequest, "url must start with http:// or https://")
			return
		}
		if len(req.URL) > 2000 {
			httpx.Error(w, http.StatusBadRequest, "url too long")
			return
		}
	default:
		httpx.Error(w, http.StatusBadRequest, "kind must be 'text' or 'link'")
		return
	}

	var communityID int64
	err := h.pool.QueryRow(r.Context(),
		`SELECT id FROM communities WHERE LOWER(name) = LOWER($1)`, name,
	).Scan(&communityID)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "community not found")
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

	var bodyArg, urlArg interface{}
	if req.Kind == "text" {
		bodyArg = req.Body
	}
	if req.Kind == "link" {
		urlArg = req.URL
	}

	var id int64
	err = h.pool.QueryRow(r.Context(), `
		INSERT INTO posts (community_id, author_id, kind, title, body, url)
		VALUES ($1, $2, $3::post_kind, $4, $5, $6)
		RETURNING id
	`, communityID, user.ID, req.Kind, req.Title, bodyArg, urlArg).Scan(&id)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}

	p, err := h.getByID(r.Context(), id, user.ID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, p)
}

func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid id")
		return
	}
	p, err := h.getByID(r.Context(), id, currentUserID(r))
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "post not found")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, p)
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

	var authorID, communityCreator int64
	err = h.pool.QueryRow(r.Context(), `
		SELECT p.author_id, c.creator_id
		FROM posts p JOIN communities c ON c.id = p.community_id
		WHERE p.id = $1 AND p.deleted_at IS NULL
	`, id).Scan(&authorID, &communityCreator)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "post not found")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	if user.ID != authorID && user.ID != communityCreator {
		httpx.Error(w, http.StatusForbidden, "not allowed")
		return
	}
	if _, err := h.pool.Exec(r.Context(),
		`UPDATE posts SET deleted_at = NOW() WHERE id = $1`, id,
	); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) ListByCommunity(w http.ResponseWriter, r *http.Request) {
	name := chi.URLParam(r, "name")
	sort := r.URL.Query().Get("sort")
	limit, offset := pagination(r)

	var communityID int64
	if err := h.pool.QueryRow(r.Context(),
		`SELECT id FROM communities WHERE LOWER(name) = LOWER($1)`, name,
	).Scan(&communityID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			httpx.Error(w, http.StatusNotFound, "community not found")
			return
		}
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	orderBy := orderByClause(sort)
	query := baseSelect + ` AND p.community_id = $2 ` + orderBy + ` LIMIT $3 OFFSET $4`
	h.runList(w, r, query, currentUserID(r), communityID, limit, offset)
}

func (h *Handler) Popular(w http.ResponseWriter, r *http.Request) {
	limit, offset := pagination(r)
	query := baseSelect + ` ` + orderByClause("hot") + ` LIMIT $2 OFFSET $3`
	h.runList(w, r, query, currentUserID(r), limit, offset)
}

func (h *Handler) Home(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.FromContext(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	limit, offset := pagination(r)
	query := baseSelect + `
	  AND p.community_id IN (SELECT community_id FROM memberships WHERE user_id = $1)
	  ` + orderByClause("new") + ` LIMIT $2 OFFSET $3`
	h.runList(w, r, query, user.ID, limit, offset)
}

func (h *Handler) Vote(w http.ResponseWriter, r *http.Request) {
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
	var body struct {
		Value int `json:"value"`
	}
	if err := httpx.DecodeJSON(r, &body); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	if body.Value != -1 && body.Value != 0 && body.Value != 1 {
		httpx.Error(w, http.StatusBadRequest, "value must be -1, 0, or 1")
		return
	}

	tx, err := h.pool.Begin(r.Context())
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	defer tx.Rollback(r.Context())

	var existing int
	err = tx.QueryRow(r.Context(),
		`SELECT value FROM post_votes WHERE post_id = $1 AND user_id = $2`,
		id, user.ID,
	).Scan(&existing)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		existing = 0
	case err != nil:
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}

	// Apply diff to ups/downs and rewrite vote row.
	dUps, dDowns := voteDelta(existing, body.Value)
	if existing == 0 && body.Value != 0 {
		if _, err := tx.Exec(r.Context(),
			`INSERT INTO post_votes (post_id, user_id, value) VALUES ($1, $2, $3)`,
			id, user.ID, body.Value,
		); err != nil {
			httpx.Error(w, http.StatusInternalServerError, "db error")
			return
		}
	} else if existing != 0 && body.Value == 0 {
		if _, err := tx.Exec(r.Context(),
			`DELETE FROM post_votes WHERE post_id = $1 AND user_id = $2`, id, user.ID,
		); err != nil {
			httpx.Error(w, http.StatusInternalServerError, "db error")
			return
		}
	} else if existing != body.Value {
		if _, err := tx.Exec(r.Context(),
			`UPDATE post_votes SET value = $3 WHERE post_id = $1 AND user_id = $2`,
			id, user.ID, body.Value,
		); err != nil {
			httpx.Error(w, http.StatusInternalServerError, "db error")
			return
		}
	}

	if dUps != 0 || dDowns != 0 {
		if _, err := tx.Exec(r.Context(),
			`UPDATE posts SET ups = ups + $2, downs = downs + $3 WHERE id = $1`,
			id, dUps, dDowns,
		); err != nil {
			httpx.Error(w, http.StatusInternalServerError, "db error")
			return
		}
	}

	if err := tx.Commit(r.Context()); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}

	p, err := h.getByID(r.Context(), id, user.ID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, p)
}

// voteDelta returns how (ups, downs) should change going from prev -> next.
func voteDelta(prev, next int) (int, int) {
	count := func(v int) (int, int) {
		switch v {
		case 1:
			return 1, 0
		case -1:
			return 0, 1
		}
		return 0, 0
	}
	pu, pd := count(prev)
	nu, nd := count(next)
	return nu - pu, nd - pd
}

func (h *Handler) getByID(ctx context.Context, id, viewerID int64) (*Post, error) {
	row := h.pool.QueryRow(ctx, baseSelect+` AND p.id = $2`, viewerID, id)
	var p Post
	if err := scanPost(row, &p); err != nil {
		return nil, err
	}
	return &p, nil
}

func (h *Handler) runList(w http.ResponseWriter, r *http.Request, query string, args ...interface{}) {
	rows, err := h.pool.Query(r.Context(), query, args...)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	defer rows.Close()
	out := make([]Post, 0, 32)
	for rows.Next() {
		var p Post
		if err := scanPost(rows, &p); err != nil {
			httpx.Error(w, http.StatusInternalServerError, "db error")
			return
		}
		out = append(out, p)
	}
	if rows.Err() != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"posts": out})
}

func orderByClause(sort string) string {
	switch sort {
	case "hot":
		return `ORDER BY (LOG(GREATEST(ABS(p.ups - p.downs), 1)) * SIGN(p.ups - p.downs)
		         + EXTRACT(EPOCH FROM p.created_at) / 45000.0) DESC`
	case "top":
		return `ORDER BY (p.ups - p.downs) DESC, p.created_at DESC`
	default: // new
		return `ORDER BY p.created_at DESC`
	}
}

func pagination(r *http.Request) (limit, offset int) {
	limit = 25
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 && v <= 100 {
		limit = v
	}
	if v, err := strconv.Atoi(r.URL.Query().Get("offset")); err == nil && v >= 0 {
		offset = v
	}
	return
}

func currentUserID(r *http.Request) int64 {
	if u, ok := auth.FromContext(r.Context()); ok {
		return u.ID
	}
	return 0
}
