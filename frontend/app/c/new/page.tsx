"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { api, ApiError } from "@/lib/api";

export default function NewCommunityPage() {
  const router = useRouter();
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      const c = await api.createCommunity({ name, description });
      router.push(`/c/${c!.name}`);
    } catch (err) {
      if (err instanceof ApiError) setError(err.message);
      else setError("something went wrong");
      setSubmitting(false);
    }
  }

  return (
    <div className="mx-auto max-w-md">
      <h1 className="mb-4 text-2xl font-semibold">Create a community</h1>
      <form onSubmit={onSubmit} className="space-y-4 rounded border bg-white p-4">
        <div>
          <label className="block text-sm font-medium">Name</label>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            required
            minLength={3}
            maxLength={24}
            pattern="[a-zA-Z0-9_]+"
            className="mt-1 w-full rounded border px-3 py-2"
            placeholder="golang"
          />
          <p className="mt-1 text-xs text-neutral-500">
            3–24 chars, letters, numbers, underscore.
          </p>
        </div>
        <div>
          <label className="block text-sm font-medium">Description</label>
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            maxLength={500}
            rows={3}
            className="mt-1 w-full rounded border px-3 py-2"
          />
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <button
          type="submit"
          disabled={submitting}
          className="rounded bg-orange-600 px-4 py-2 text-white hover:bg-orange-700 disabled:opacity-50"
        >
          {submitting ? "Creating…" : "Create"}
        </button>
      </form>
    </div>
  );
}
