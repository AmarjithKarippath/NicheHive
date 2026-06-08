"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api, User } from "@/lib/api";
import { FeedbackModal } from "./FeedbackModal";

export function Navbar() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [showFeedback, setShowFeedback] = useState(false);

  useEffect(() => {
    api
      .me()
      .then((u) => setUser(u))
      .catch(() => setUser(null))
      .finally(() => setLoading(false));
  }, []);

  async function logout() {
    await api.logout();
    setUser(null);
    window.location.href = "/";
  }

  return (
    <nav className="border-b bg-white">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-3">
        <Link href="/" className="text-xl font-bold text-orange-600">
          NicheHive
        </Link>
        <div className="flex items-center gap-3 text-sm">
          <button
            onClick={() => setShowFeedback(true)}
            className="rounded border px-3 py-1 text-neutral-600 hover:bg-neutral-100"
          >
            Feedback
          </button>
          {loading ? null : user ? (
            <>
              <Link
                href="/c/new"
                className="rounded border px-3 py-1 hover:bg-neutral-100"
              >
                Create community
              </Link>
              <span className="text-neutral-600">u/{user.username}</span>
              <button
                onClick={logout}
                className="rounded border px-3 py-1 hover:bg-neutral-100"
              >
                Log out
              </button>
            </>
          ) : (
            <a
              href={api.loginUrl()}
              className="rounded bg-orange-600 px-3 py-1 text-white hover:bg-orange-700"
            >
              Sign in with Google
            </a>
          )}
        </div>
      </div>
      {showFeedback && <FeedbackModal onClose={() => setShowFeedback(false)} />}
    </nav>
  );
}
