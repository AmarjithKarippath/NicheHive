package feedback

import (
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/amar/reddit/internal/auth"
	"github.com/amar/reddit/internal/httpx"
)

type Handler struct {
	pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Handler {
	return &Handler{pool: pool}
}

type submitReq struct {
	Kind    string `json:"kind"`
	Message string `json:"message"`
	PageURL string `json:"page_url,omitempty"`
}

func (h *Handler) Submit(w http.ResponseWriter, r *http.Request) {
	var req submitReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid body")
		return
	}
	req.Message = strings.TrimSpace(req.Message)
	req.PageURL = strings.TrimSpace(req.PageURL)

	switch req.Kind {
	case "bug", "enhancement", "other":
	default:
		httpx.Error(w, http.StatusBadRequest, "kind must be bug, enhancement, or other")
		return
	}
	if req.Message == "" || len(req.Message) > 5000 {
		httpx.Error(w, http.StatusBadRequest, "message must be 1-5000 chars")
		return
	}
	if len(req.PageURL) > 2000 {
		req.PageURL = req.PageURL[:2000]
	}

	var userID *int64
	if u, ok := auth.FromContext(r.Context()); ok {
		userID = &u.ID
	}

	ua := r.Header.Get("User-Agent")
	if len(ua) > 500 {
		ua = ua[:500]
	}

	if _, err := h.pool.Exec(r.Context(), `
		INSERT INTO feedback (user_id, kind, message, user_agent, page_url)
		VALUES ($1, $2::feedback_kind, $3, NULLIF($4, ''), NULLIF($5, ''))
	`, userID, req.Kind, req.Message, ua, req.PageURL); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "db error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
