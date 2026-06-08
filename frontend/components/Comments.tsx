"use client";

import { useEffect, useMemo, useState } from "react";
import { api, ApiError, Comment, User } from "@/lib/api";
import { Linkify } from "./Linkify";

type Node = Comment & { children: Node[] };

function buildTree(list: Comment[]): Node[] {
  const map = new Map<number, Node>();
  list.forEach((c) => map.set(c.id, { ...c, children: [] }));
  const roots: Node[] = [];
  list.forEach((c) => {
    const node = map.get(c.id)!;
    if (c.parent_id && map.has(c.parent_id)) {
      map.get(c.parent_id)!.children.push(node);
    } else {
      roots.push(node);
    }
  });
  return roots;
}

export function Comments({ postId }: { postId: number }) {
  const [comments, setComments] = useState<Comment[]>([]);
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [body, setBody] = useState("");

  useEffect(() => {
    api.me().then(setUser).catch(() => setUser(null));
    api
      .listComments(postId)
      .then((res) => setComments(res?.comments ?? []))
      .catch((err) =>
        setError(err instanceof ApiError ? err.message : "failed to load"),
      )
      .finally(() => setLoading(false));
  }, [postId]);

  const tree = useMemo(() => buildTree(comments), [comments]);

  async function submitTopLevel(e: React.FormEvent) {
    e.preventDefault();
    if (!body.trim()) return;
    try {
      const c = await api.createComment(postId, { body });
      if (c) {
        setComments((prev) => [...prev, c]);
        setBody("");
      }
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        window.location.href = api.loginUrl();
      }
    }
  }

  function onReply(c: Comment) {
    setComments((prev) => [...prev, c]);
  }

  function onDelete(id: number) {
    setComments((prev) =>
      prev.map((c) => (c.id === id ? { ...c, deleted: true, body: "[deleted]" } : c)),
    );
  }

  return (
    <section className="space-y-4">
      {user ? (
        <form onSubmit={submitTopLevel} className="space-y-2 rounded border bg-white p-3">
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            rows={3}
            placeholder="Add a comment"
            className="w-full rounded border px-3 py-2 text-sm"
          />
          <div className="flex justify-end">
            <button
              type="submit"
              className="rounded bg-orange-600 px-3 py-1 text-sm text-white hover:bg-orange-700"
            >
              Comment
            </button>
          </div>
        </form>
      ) : (
        <p className="text-sm text-neutral-500">
          <a href={api.loginUrl()} className="text-orange-600 hover:underline">
            Sign in
          </a>{" "}
          to comment.
        </p>
      )}

      {loading && <p className="text-neutral-500">Loading comments…</p>}
      {error && <p className="text-red-600">{error}</p>}
      {!loading && tree.length === 0 && (
        <p className="text-neutral-500">No comments yet.</p>
      )}
      <ul className="space-y-3">
        {tree.map((c) => (
          <CommentNode
            key={c.id}
            node={c}
            currentUser={user}
            postId={postId}
            onReply={onReply}
            onDelete={onDelete}
          />
        ))}
      </ul>
    </section>
  );
}

function CommentNode({
  node,
  currentUser,
  postId,
  onReply,
  onDelete,
}: {
  node: Node;
  currentUser: User | null;
  postId: number;
  onReply: (c: Comment) => void;
  onDelete: (id: number) => void;
}) {
  const [showReply, setShowReply] = useState(false);
  const [replyBody, setReplyBody] = useState("");

  async function submitReply(e: React.FormEvent) {
    e.preventDefault();
    if (!replyBody.trim()) return;
    try {
      const c = await api.createComment(postId, {
        body: replyBody,
        parent_id: node.id,
      });
      if (c) {
        onReply(c);
        setReplyBody("");
        setShowReply(false);
      }
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        window.location.href = api.loginUrl();
      }
    }
  }

  async function del() {
    try {
      await api.deleteComment(node.id);
      onDelete(node.id);
    } catch {
      /* ignore */
    }
  }

  const canDelete =
    !node.deleted && currentUser && currentUser.id === node.author_id;

  return (
    <li className="border-l pl-3">
      <div className="text-xs text-neutral-500">
        u/{node.author_name} · {new Date(node.created_at).toLocaleString()}
      </div>
      <div className={`whitespace-pre-wrap text-sm ${node.deleted ? "italic text-neutral-500" : ""}`}>
        {node.deleted ? node.body : <Linkify text={node.body} />}
      </div>
      <div className="mt-1 flex gap-3 text-xs text-neutral-500">
        {currentUser && !node.deleted && (
          <button onClick={() => setShowReply((s) => !s)} className="hover:underline">
            Reply
          </button>
        )}
        {canDelete && (
          <button onClick={del} className="hover:underline">
            Delete
          </button>
        )}
      </div>
      {showReply && (
        <form onSubmit={submitReply} className="mt-2 space-y-1">
          <textarea
            value={replyBody}
            onChange={(e) => setReplyBody(e.target.value)}
            rows={2}
            className="w-full rounded border px-2 py-1 text-sm"
          />
          <div className="flex gap-2">
            <button
              type="submit"
              className="rounded bg-orange-600 px-2 py-1 text-xs text-white hover:bg-orange-700"
            >
              Reply
            </button>
            <button
              type="button"
              onClick={() => setShowReply(false)}
              className="rounded border px-2 py-1 text-xs hover:bg-neutral-100"
            >
              Cancel
            </button>
          </div>
        </form>
      )}
      {node.children.length > 0 && (
        <ul className="mt-2 space-y-3">
          {node.children.map((child) => (
            <CommentNode
              key={child.id}
              node={child}
              currentUser={currentUser}
              postId={postId}
              onReply={onReply}
              onDelete={onDelete}
            />
          ))}
        </ul>
      )}
    </li>
  );
}
