"use client";

import Link from "next/link";
import { useState } from "react";
import { api, ApiError, Post } from "@/lib/api";
import { Linkify } from "./Linkify";

export function PostCard({ post: initial }: { post: Post }) {
  const [post, setPost] = useState(initial);
  const [voting, setVoting] = useState(false);

  async function vote(target: 1 | -1) {
    if (voting) return;
    setVoting(true);
    const next = post.user_vote === target ? 0 : target;
    try {
      const updated = await api.votePost(post.id, next);
      if (updated) setPost(updated);
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        window.location.href = api.loginUrl();
      }
    } finally {
      setVoting(false);
    }
  }

  return (
    <article className="flex gap-3 rounded border bg-white p-3">
      <div className="flex-1">
        <div className="text-xs text-neutral-500">
          <Link href={`/c/${post.community_name}`} className="font-medium text-neutral-700 hover:underline">
            c/{post.community_name}
          </Link>
          <span> · u/{post.author_name} · {new Date(post.created_at).toLocaleString()}</span>
        </div>
        <Link href={`/p/${post.id}`} className="block text-lg font-medium hover:underline">
          {post.title}
        </Link>
        {post.body && (
          <p className="mt-1 line-clamp-3 whitespace-pre-wrap text-sm text-neutral-700">
            <Linkify text={post.body} />
          </p>
        )}
        {post.kind === "link" && post.url && (
          <a
            href={post.url}
            target="_blank"
            rel="noopener noreferrer nofollow"
            className="break-all text-sm text-blue-600 hover:underline"
          >
            {post.url}
          </a>
        )}
      </div>
      <div className="flex items-center gap-2 text-xs">
        <button
          onClick={() => vote(1)}
          className={`grayscale opacity-60 hover:opacity-100 ${post.user_vote === 1 ? "grayscale-0 opacity-100" : ""}`}
          aria-label="upvote"
        >
          👍
        </button>
        <button
          onClick={() => vote(-1)}
          className={`grayscale opacity-60 hover:opacity-100 ${post.user_vote === -1 ? "grayscale-0 opacity-100" : ""}`}
          aria-label="downvote"
        >
          👎
        </button>
      </div>
    </article>
  );
}
