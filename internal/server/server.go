package server

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/amar/reddit/internal/auth"
	"github.com/amar/reddit/internal/comments"
	"github.com/amar/reddit/internal/communities"
	"github.com/amar/reddit/internal/config"
	"github.com/amar/reddit/internal/posts"
)

func New(cfg *config.Config, pool *pgxpool.Pool) http.Handler {
	r := chi.NewRouter()

	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(15 * time.Second))

	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{cfg.FrontendURL},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Content-Type", "Authorization"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	r.Get("/healthz", func(w http.ResponseWriter, req *http.Request) {
		if err := pool.Ping(req.Context()); err != nil {
			http.Error(w, "db down", http.StatusServiceUnavailable)
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	authH := auth.New(cfg, pool)
	commH := communities.New(pool)
	postH := posts.New(pool)
	cmtH := comments.New(pool)

	r.Route("/api/v1", func(r chi.Router) {
		// auth (public)
		r.Get("/auth/google/login", authH.Login)
		r.Get("/auth/google/callback", authH.Callback)
		r.Post("/auth/logout", authH.Logout)

		// me (auth required)
		r.Group(func(r chi.Router) {
			r.Use(authH.Required)
			r.Get("/me", authH.Me)
		})

		// communities, posts, comments, votes — to be implemented next
		r.Group(func(r chi.Router) {
			r.Use(authH.Optional)

			r.Post("/communities", commH.Create)
			r.Get("/communities/{name}", commH.Get)
			r.Post("/communities/{name}/join", commH.Join)
			r.Post("/communities/{name}/leave", commH.Leave)

			r.Post("/communities/{name}/posts", postH.Create)
			r.Get("/communities/{name}/posts", postH.ListByCommunity)
			r.Get("/posts/{id}", postH.Get)
			r.Delete("/posts/{id}", postH.Delete)

			r.Get("/feeds/home", postH.Home)
			r.Get("/feeds/popular", postH.Popular)

			r.Post("/posts/{id}/comments", cmtH.Create)
			r.Get("/posts/{id}/comments", cmtH.ListByPost)
			r.Delete("/comments/{id}", cmtH.Delete)

			r.Post("/posts/{id}/vote", postH.Vote)

			r.Post("/communities/{name}/bans", notImplemented)
			r.Delete("/communities/{name}/bans/{username}", notImplemented)

			r.Get("/users/{username}", notImplemented)
			r.Get("/search", notImplemented)
		})
	})

	return r
}

func notImplemented(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotImplemented, map[string]string{"error": "not implemented"})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
