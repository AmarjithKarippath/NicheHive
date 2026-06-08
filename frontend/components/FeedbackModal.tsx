"use client";

import { useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";

type Kind = "bug" | "enhancement" | "other";

export function FeedbackModal({ onClose }: { onClose: () => void }) {
  const [kind, setKind] = useState<Kind>("bug");
  const [message, setMessage] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!message.trim()) return;
    setSubmitting(true);
    setError(null);
    try {
      await api.submitFeedback({
        kind,
        message,
        page_url: typeof window !== "undefined" ? window.location.href : "",
      });
      setDone(true);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "failed to send");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      onClick={onClose}
    >
      <div
        className="w-full max-w-md rounded-lg bg-white p-5 shadow-lg"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-lg font-semibold">Send feedback</h2>
          <button
            onClick={onClose}
            className="text-neutral-400 hover:text-neutral-700"
            aria-label="Close"
          >
            ✕
          </button>
        </div>

        {done ? (
          <div className="space-y-3 py-2">
            <p className="text-sm text-neutral-700">
              Thanks — your feedback was received.
            </p>
            <button
              onClick={onClose}
              className="rounded bg-orange-600 px-3 py-1 text-sm text-white hover:bg-orange-700"
            >
              Close
            </button>
          </div>
        ) : (
          <form onSubmit={onSubmit} className="space-y-3">
            <div>
              <label className="block text-sm font-medium">Type</label>
              <div className="mt-1 flex gap-2 text-sm">
                {(["bug", "enhancement", "other"] as const).map((k) => (
                  <button
                    key={k}
                    type="button"
                    onClick={() => setKind(k)}
                    className={`rounded px-3 py-1 capitalize ${
                      kind === k ? "bg-neutral-200 font-medium" : "border"
                    }`}
                  >
                    {k}
                  </button>
                ))}
              </div>
            </div>
            <div>
              <label className="block text-sm font-medium">Message</label>
              <textarea
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                rows={5}
                required
                maxLength={5000}
                placeholder={
                  kind === "bug"
                    ? "What happened? What did you expect?"
                    : kind === "enhancement"
                    ? "What would you like to see?"
                    : "Anything on your mind."
                }
                className="mt-1 w-full rounded border px-3 py-2 text-sm"
              />
            </div>
            {error && <p className="text-sm text-red-600">{error}</p>}
            <div className="flex justify-end gap-2">
              <button
                type="button"
                onClick={onClose}
                className="rounded border px-3 py-1 text-sm hover:bg-neutral-100"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={submitting || !message.trim()}
                className="rounded bg-orange-600 px-3 py-1 text-sm text-white hover:bg-orange-700 disabled:opacity-50"
              >
                {submitting ? "Sending…" : "Send"}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
