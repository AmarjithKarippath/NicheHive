"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { api, ApiError, Community, Post } from "@/lib/api";
import { PostList } from "@/components/PostList";

type Sort = "new" | "hot" | "top";

export default function CommunityPage() {
  const params = useParams<{ name: string }>();
  const name = params.name;
  const [community, setCommunity] = useState<Community | null>(null);
  const [posts, setPosts] = useState<Post[]>([]);
  const [sort, setSort] = useState<Sort>("new");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [loadingPosts, setLoadingPosts] = useState(true);

  useEffect(() => {
    setError(null);
    api
      .getCommunity(name)
      .then((c) => setCommunity(c))
      .catch((err) => {
        if (err instanceof ApiError) setError(err.message);
        else setError("failed to load");
      });
  }, [name]);

  useEffect(() => {
    let cancelled = false;
    setLoadingPosts(true);
    api
      .listCommunityPosts(name, sort)
      .then((res) => !cancelled && setPosts(res?.posts ?? []))
      .catch(() => !cancelled && setPosts([]))
      .finally(() => !cancelled && setLoadingPosts(false));
    return () => {
      cancelled = true;
    };
  }, [name, sort]);

  async function toggleMembership() {
    if (!community) return;
    setPending(true);
    try {
      if (community.is_member) {
        await api.leaveCommunity(community.name);
        setCommunity({
          ...community,
          is_member: false,
          member_count: community.member_count - 1,
        });
      } else {
        await api.joinCommunity(community.name);
        setCommunity({
          ...community,
          is_member: true,
          member_count: community.member_count + 1,
        });
      }
    } catch (err) {
      if (err instanceof ApiError) setError(err.message);
    } finally {
      setPending(false);
    }
  }

  if (error && !community) return <p className="text-red-600">{error}</p>;
  if (!community) return <p>Loading…</p>;

  return (
    <div className="space-y-4">
      <header className="rounded border bg-white p-4">
        <div className="flex items-start justify-between gap-4">
          <div>
            <h1 className="text-2xl font-semibold">c/{community.name}</h1>
            <p className="mt-1 text-neutral-600">{community.description}</p>
            <p className="mt-2 text-sm text-neutral-500">
              {community.member_count}{" "}
              {community.member_count === 1 ? "member" : "members"}
            </p>
          </div>
          <div className="flex flex-col items-end gap-2">
            <button
              onClick={toggleMembership}
              disabled={pending}
              className={`rounded px-4 py-2 text-sm ${
                community.is_member
                  ? "border hover:bg-neutral-100"
                  : "bg-orange-600 text-white hover:bg-orange-700"
              } disabled:opacity-50`}
            >
              {community.is_member ? "Leave" : "Join"}
            </button>
            <Link
              href={`/c/${community.name}/submit`}
              className="rounded border px-4 py-2 text-sm hover:bg-neutral-100"
            >
              New post
            </Link>
          </div>
        </div>
      </header>

      <div className="flex gap-2 border-b text-sm">
        {(["new", "hot", "top"] as const).map((s) => (
          <button
            key={s}
            onClick={() => setSort(s)}
            className={`px-3 py-2 capitalize ${
              sort === s
                ? "border-b-2 border-orange-600 font-medium"
                : "text-neutral-500 hover:text-neutral-800"
            }`}
          >
            {s}
          </button>
        ))}
      </div>

      {loadingPosts ? (
        <p className="text-neutral-500">Loading…</p>
      ) : (
        <PostList posts={posts} />
      )}
    </div>
  );
}
