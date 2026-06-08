"use client";

import { Post } from "@/lib/api";
import { PostCard } from "./PostCard";

export function PostList({ posts }: { posts: Post[] }) {
  if (posts.length === 0) {
    return <p className="text-neutral-500">No posts yet.</p>;
  }
  return (
    <div className="space-y-3">
      {posts.map((p) => (
        <PostCard key={p.id} post={p} />
      ))}
    </div>
  );
}
