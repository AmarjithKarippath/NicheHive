"use client";

import { useEffect, useState } from "react";
import { api, ApiError, Post } from "@/lib/api";
import { PostList } from "@/components/PostList";

type Tab = "popular" | "home";

export default function HomePage() {
  const [tab, setTab] = useState<Tab>("popular");
  const [posts, setPosts] = useState<Post[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    const fetcher = tab === "home" ? api.homeFeed : api.popularFeed;
    fetcher()
      .then((res) => {
        if (!cancelled) setPosts(res?.posts ?? []);
      })
      .catch((err) => {
        if (cancelled) return;
        if (err instanceof ApiError && err.status === 401 && tab === "home") {
          setError("Sign in to see your home feed.");
        } else {
          setError(err.message ?? "failed to load");
        }
      })
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, [tab]);

  return (
    <div className="space-y-4">
      <div className="flex gap-2 border-b text-sm">
        {(["popular", "home"] as const).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`px-3 py-2 ${
              tab === t
                ? "border-b-2 border-orange-600 font-medium"
                : "text-neutral-500 hover:text-neutral-800"
            }`}
          >
            {t === "popular" ? "Popular" : "Home"}
          </button>
        ))}
      </div>
      {loading && <p className="text-neutral-500">Loading…</p>}
      {error && <p className="text-red-600">{error}</p>}
      {!loading && !error && <PostList posts={posts} />}
    </div>
  );
}
