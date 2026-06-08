package auth

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"

	"github.com/amar/reddit/internal/config"
)

const (
	sessionCookie     = "rd_session"
	stateCookie       = "rd_oauth_state"
	sessionTTL        = 30 * 24 * time.Hour
	stateTTL          = 10 * time.Minute
	googleUserInfoURL = "https://www.googleapis.com/oauth2/v3/userinfo"
)

type User struct {
	ID        int64     `json:"id"`
	Username  string    `json:"username"`
	Email     string    `json:"email"`
	AvatarURL string    `json:"avatar_url,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

type Handler struct {
	cfg   *config.Config
	pool  *pgxpool.Pool
	oauth *oauth2.Config
}

func New(cfg *config.Config, pool *pgxpool.Pool) *Handler {
	return &Handler{
		cfg:  cfg,
		pool: pool,
		oauth: &oauth2.Config{
			ClientID:     cfg.GoogleClientID,
			ClientSecret: cfg.GoogleClientSecret,
			RedirectURL:  cfg.GoogleRedirectURL,
			Scopes:       []string{"openid", "email", "profile"},
			Endpoint:     google.Endpoint,
		},
	}
}

func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	state, err := randomToken(24)
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	http.SetCookie(w, &http.Cookie{
		Name:     stateCookie,
		Value:    state,
		Path:     "/",
		HttpOnly: true,
		Secure:   r.TLS != nil,
		SameSite: http.SameSiteLaxMode,
		Expires:  time.Now().Add(stateTTL),
	})
	http.Redirect(w, r, h.oauth.AuthCodeURL(state), http.StatusTemporaryRedirect)
}

func (h *Handler) Callback(w http.ResponseWriter, r *http.Request) {
	stateCk, err := r.Cookie(stateCookie)
	if err != nil || stateCk.Value == "" || stateCk.Value != r.URL.Query().Get("state") {
		http.Error(w, "invalid oauth state", http.StatusBadRequest)
		return
	}
	// clear state cookie
	http.SetCookie(w, &http.Cookie{Name: stateCookie, Value: "", Path: "/", MaxAge: -1})

	code := r.URL.Query().Get("code")
	if code == "" {
		http.Error(w, "missing code", http.StatusBadRequest)
		return
	}

	tok, err := h.oauth.Exchange(r.Context(), code)
	if err != nil {
		http.Error(w, "token exchange failed", http.StatusBadGateway)
		return
	}

	profile, err := fetchGoogleProfile(r.Context(), h.oauth.Client(r.Context(), tok))
	if err != nil {
		http.Error(w, "failed to fetch profile", http.StatusBadGateway)
		return
	}

	user, err := h.upsertUser(r.Context(), profile)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}

	session, err := h.createSession(r.Context(), user.ID)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}

	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookie,
		Value:    session,
		Path:     "/",
		HttpOnly: true,
		Secure:   r.TLS != nil,
		SameSite: http.SameSiteLaxMode,
		Expires:  time.Now().Add(sessionTTL),
	})

	http.Redirect(w, r, h.cfg.FrontendURL, http.StatusTemporaryRedirect)
}

func (h *Handler) Logout(w http.ResponseWriter, r *http.Request) {
	if ck, err := r.Cookie(sessionCookie); err == nil && ck.Value != "" {
		_, _ = h.pool.Exec(r.Context(), `DELETE FROM sessions WHERE token = $1`, ck.Value)
	}
	http.SetCookie(w, &http.Cookie{Name: sessionCookie, Value: "", Path: "/", MaxAge: -1})
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	user, ok := FromContext(r.Context())
	if !ok {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(user)
}

// --- middleware ---

type ctxKey struct{}

func FromContext(ctx context.Context) (*User, bool) {
	u, ok := ctx.Value(ctxKey{}).(*User)
	return u, ok
}

// Required rejects unauthenticated requests with 401.
func (h *Handler) Required(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, err := h.userFromRequest(r)
		if err != nil || user == nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, user)))
	})
}

// Optional attaches user if a valid session exists, otherwise continues anonymously.
func (h *Handler) Optional(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, _ := h.userFromRequest(r)
		ctx := r.Context()
		if user != nil {
			ctx = context.WithValue(ctx, ctxKey{}, user)
		}
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (h *Handler) userFromRequest(r *http.Request) (*User, error) {
	ck, err := r.Cookie(sessionCookie)
	if err != nil || ck.Value == "" {
		return nil, nil
	}
	var u User
	err = h.pool.QueryRow(r.Context(), `
		SELECT u.id, u.username, u.email, COALESCE(u.avatar_url, ''), u.created_at
		FROM sessions s
		JOIN users u ON u.id = s.user_id
		WHERE s.token = $1 AND s.expires_at > NOW()
	`, ck.Value).Scan(&u.ID, &u.Username, &u.Email, &u.AvatarURL, &u.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &u, nil
}

// --- internals ---

type googleProfile struct {
	Sub       string `json:"sub"`
	Email     string `json:"email"`
	Name      string `json:"name"`
	GivenName string `json:"given_name"`
	Picture   string `json:"picture"`
}

func fetchGoogleProfile(ctx context.Context, client *http.Client) (*googleProfile, error) {
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, googleUserInfoURL, nil)
	res, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(res.Body)
		return nil, fmt.Errorf("userinfo status %d: %s", res.StatusCode, string(body))
	}
	var p googleProfile
	if err := json.NewDecoder(res.Body).Decode(&p); err != nil {
		return nil, err
	}
	if p.Sub == "" || p.Email == "" {
		return nil, errors.New("incomplete google profile")
	}
	return &p, nil
}

func (h *Handler) upsertUser(ctx context.Context, p *googleProfile) (*User, error) {
	tx, err := h.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var u User
	err = tx.QueryRow(ctx, `
		SELECT id, username, email, COALESCE(avatar_url, ''), created_at
		FROM users WHERE google_id = $1
	`, p.Sub).Scan(&u.ID, &u.Username, &u.Email, &u.AvatarURL, &u.CreatedAt)
	if err == nil {
		return &u, tx.Commit(ctx)
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}

	username, err := pickUsername(ctx, tx, p)
	if err != nil {
		return nil, err
	}
	err = tx.QueryRow(ctx, `
		INSERT INTO users (google_id, email, username, avatar_url)
		VALUES ($1, $2, $3, NULLIF($4, ''))
		RETURNING id, username, email, COALESCE(avatar_url, ''), created_at
	`, p.Sub, p.Email, username, p.Picture).
		Scan(&u.ID, &u.Username, &u.Email, &u.AvatarURL, &u.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &u, tx.Commit(ctx)
}

var usernameAlnum = regexp.MustCompile(`[^a-z0-9]+`)

// pickUsername builds "<first 4 letters of first name><unique number>".
// The prefix is lowercased, stripped to [a-z0-9], padded to >=4 chars.
// The numeric suffix is the smallest free integer for that prefix.
func pickUsername(ctx context.Context, tx pgx.Tx, p *googleProfile) (string, error) {
	source := strings.ToLower(p.GivenName)
	if source == "" {
		source = strings.ToLower(strings.SplitN(p.Name, " ", 2)[0])
	}
	if source == "" {
		source = strings.ToLower(strings.SplitN(p.Email, "@", 2)[0])
	}
	clean := usernameAlnum.ReplaceAllString(source, "")
	if clean == "" {
		clean = "user"
	}
	prefix := clean
	if len(prefix) > 4 {
		prefix = prefix[:4]
	}
	for len(prefix) < 4 {
		prefix += "x"
	}

	// Find the smallest free numeric suffix for this prefix.
	var maxN int
	err := tx.QueryRow(ctx, `
		SELECT COALESCE(MAX((SUBSTRING(username FROM '^`+prefix+`(\d+)$'))::int), 0)
		FROM users
		WHERE username ~ ('^`+prefix+`\d+$')
	`).Scan(&maxN)
	if err != nil {
		return "", fmt.Errorf("scan max suffix: %w", err)
	}

	for n := maxN + 1; n < maxN+1000; n++ {
		candidate := fmt.Sprintf("%s%d", prefix, n)
		var exists bool
		if err := tx.QueryRow(ctx,
			`SELECT EXISTS(SELECT 1 FROM users WHERE username = $1)`, candidate,
		).Scan(&exists); err != nil {
			return "", err
		}
		if !exists {
			return candidate, nil
		}
	}
	return "", errors.New("could not pick username")
}

func (h *Handler) createSession(ctx context.Context, userID int64) (string, error) {
	token, err := randomToken(32)
	if err != nil {
		return "", err
	}
	_, err = h.pool.Exec(ctx, `
		INSERT INTO sessions (token, user_id, expires_at) VALUES ($1, $2, $3)
	`, token, userID, time.Now().Add(sessionTTL))
	if err != nil {
		return "", err
	}
	return token, nil
}

func randomToken(nBytes int) (string, error) {
	b := make([]byte, nBytes)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
