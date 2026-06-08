export const API_URL =
  process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080/api/v1";

export type User = {
  id: number;
  username: string;
  email: string;
  avatar_url?: string;
  created_at: string;
};

export type Community = {
  id: number;
  name: string;
  description: string;
  creator_id: number;
  created_at: string;
  member_count: number;
  is_member: boolean;
};

export type Post = {
  id: number;
  community_id: number;
  community_name: string;
  author_id: number;
  author_name: string;
  kind: "text" | "link";
  title: string;
  body?: string | null;
  url?: string | null;
  ups: number;
  downs: number;
  score: number;
  comment_count: number;
  user_vote: number;
  created_at: string;
};

export type Comment = {
  id: number;
  post_id: number;
  parent_id?: number | null;
  author_id: number;
  author_name: string;
  body: string;
  deleted: boolean;
  created_at: string;
};

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

async function request<T>(
  path: string,
  init: RequestInit = {},
): Promise<T | null> {
  const res = await fetch(`${API_URL}${path}`, {
    ...init,
    credentials: "include",
    headers: {
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
    cache: "no-store",
  });
  if (res.status === 204) return null;
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) {
    const msg = (data && (data as { error?: string }).error) || res.statusText;
    throw new ApiError(res.status, msg);
  }
  return data as T;
}

export const api = {
  me: () => request<User>("/me"),
  logout: () => request<null>("/auth/logout", { method: "POST" }),
  loginUrl: () => `${API_URL}/auth/google/login`,

  getCommunity: (name: string) => request<Community>(`/communities/${name}`),
  createCommunity: (input: { name: string; description: string }) =>
    request<Community>("/communities", {
      method: "POST",
      body: JSON.stringify(input),
    }),
  joinCommunity: (name: string) =>
    request<null>(`/communities/${name}/join`, { method: "POST" }),
  leaveCommunity: (name: string) =>
    request<null>(`/communities/${name}/leave`, { method: "POST" }),

  listCommunityPosts: (name: string, sort: "new" | "hot" | "top" = "new") =>
    request<{ posts: Post[] }>(`/communities/${name}/posts?sort=${sort}`),
  homeFeed: () => request<{ posts: Post[] }>(`/feeds/home`),
  popularFeed: () => request<{ posts: Post[] }>(`/feeds/popular`),

  createPost: (
    community: string,
    input: { kind: "text" | "link"; title: string; body?: string; url?: string },
  ) =>
    request<Post>(`/communities/${community}/posts`, {
      method: "POST",
      body: JSON.stringify(input),
    }),
  getPost: (id: number | string) => request<Post>(`/posts/${id}`),
  deletePost: (id: number) =>
    request<null>(`/posts/${id}`, { method: "DELETE" }),
  votePost: (id: number, value: -1 | 0 | 1) =>
    request<Post>(`/posts/${id}/vote`, {
      method: "POST",
      body: JSON.stringify({ value }),
    }),

  listComments: (postId: number | string) =>
    request<{ comments: Comment[] }>(`/posts/${postId}/comments`),
  createComment: (
    postId: number | string,
    input: { body: string; parent_id?: number },
  ) =>
    request<Comment>(`/posts/${postId}/comments`, {
      method: "POST",
      body: JSON.stringify(input),
    }),
  deleteComment: (id: number) =>
    request<null>(`/comments/${id}`, { method: "DELETE" }),
};
