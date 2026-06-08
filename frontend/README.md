# NicheHive frontend

Next.js 14 (App Router) + TypeScript + Tailwind. Talks to the Go API.

## Setup
```
cd frontend
cp .env.local.example .env.local
npm install
npm run dev
```
Open http://localhost:3000.

The backend must be running at the URL in `NEXT_PUBLIC_API_URL` (default `http://localhost:8080/api/v1`). Sessions use cookies, so `fetch` uses `credentials: "include"`.

## Pages
- `/` — home (posts feed TBD)
- `/c/new` — create a community
- `/c/[name]` — community page (join/leave)

## Auth
- "Sign in with Google" navigates the browser to the backend OAuth endpoint; the backend redirects to Google, then back to the callback, then back to this frontend with a `rd_session` cookie set.
- `Navbar` calls `/me` on mount to determine login state.
