"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { api, ApiError, Post, User } from "@/lib/api";
import { Comments } from "@/components/Comments";
import { Linkify } from "@/components/Linkify";

export default function PostPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const id = Number(params.id);
  const [post, setPost] = useState<Post | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [voting, setVoting] = useState(false);

  useEffect(() => {
    api.me().then(setUser).catch(() => setUser(null));
    api
      .getPost(id)
      .then(setPost)
      .catch((err) =>
        setError(err instanceof ApiError ? err.message : "failed to load"),
      );
  }, [id]);

  async function vote(target: 1 | -1) {
    if (!post || voting) return;
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

  async function del() {
    if (!post) return;
    if (!confirm("Delete this post?")) return;
    try {
      await api.deletePost(post.id);
      router.push(`/c/${post.community_name}`);
    } catch (err) {
      if (err instanceof ApiError) setError(err.message);
    }
  }

  if (error) return <p className="text-red-600">{error}</p>;
  if (!post) return <p>Loading…</p>;

  const canDelete = user && user.id === post.author_id;

  return (
    <div className="space-y-4">
      <article className="flex gap-3 rounded border bg-white p-4">
        <div className="flex-1">
          <div className="text-xs text-neutral-500">
            <Link href={`/c/${post.community_name}`} className="font-medium text-neutral-700 hover:underline">
              c/{post.community_name}
            </Link>
            <span>
              {" "}
              · u/{post.author_name} · {new Date(post.created_at).toLocaleString()}
            </span>
          </div>
          <h1 className="mt-1 text-xl font-semibold">{post.title}</h1>
          {post.body && (
            <p className="mt-2 whitespace-pre-wrap text-neutral-800">
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
          {canDelete && (
            <div className="mt-3 text-xs">
              <button onClick={del} className="text-red-600 hover:underline">
                Delete
              </button>
            </div>
          )}
        </div>
        <div className="flex items-center gap-2 text-sm">
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

      <Comments postId={post.id} />
    </div>
  );
}
