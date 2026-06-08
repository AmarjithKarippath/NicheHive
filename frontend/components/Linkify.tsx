import React from "react";

const URL_RE = /(https?:\/\/[^\s<]+[^\s.,;:!?<)\]'"])/gi;

export function Linkify({ text, className }: { text: string; className?: string }) {
  const parts: React.ReactNode[] = [];
  let last = 0;
  let i = 0;
  text.replace(URL_RE, (match, _g, offset: number) => {
    if (offset > last) parts.push(text.slice(last, offset));
    parts.push(
      <a
        key={`l${i++}`}
        href={match}
        target="_blank"
        rel="noopener noreferrer nofollow"
        className="text-blue-600 hover:underline"
      >
        {match}
      </a>,
    );
    last = offset + match.length;
    return match;
  });
  if (last < text.length) parts.push(text.slice(last));
  return <span className={className}>{parts}</span>;
}
