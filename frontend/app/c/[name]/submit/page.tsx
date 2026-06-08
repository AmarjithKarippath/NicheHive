"use client";

import { useParams, useRouter } from "next/navigation";
import { useState } from "react";
import { api, ApiError } from "@/lib/api";

export default function SubmitPage() {
  const params = useParams<{ name: string }>();
  const router = useRouter();
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      const p = await api.createPost(params.name, {
        kind: "text",
        title,
        body,
      });
      router.push(`/p/${p!.id}`);
    } catch (err) {
      if (err instanceof ApiError) setError(err.message);
      else setError("something went wrong");
      setSubmitting(false);
    }
  }

  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="mb-4 text-2xl font-semibold">New post in c/{params.name}</h1>
      <form onSubmit={onSubmit} className="space-y-4 rounded border bg-white p-4">
        <div>
          <label className="block text-sm font-medium">Title</label>
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            required
            maxLength={300}
            className="mt-1 w-full rounded border px-3 py-2"
          />
        </div>
        <div>
          <label className="block text-sm font-medium">Body</label>
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            required
            maxLength={10000}
            rows={8}
            placeholder="Write your post. Paste any links inline — they’ll be clickable."
            className="mt-1 w-full rounded border px-3 py-2"
          />
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <button
          type="submit"
          disabled={submitting}
          className="rounded bg-orange-600 px-4 py-2 text-white hover:bg-orange-700 disabled:opacity-50"
        >
          {submitting ? "Posting…" : "Post"}
        </button>
      </form>
    </div>
  );
}
