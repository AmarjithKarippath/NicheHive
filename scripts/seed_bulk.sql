-- ============================================================
-- Bulk seed: 50 users, 10 communities, 100 posts, ~400 comments
-- ============================================================

BEGIN;

-- ---------- 50 users (10 prefixes x 5) ----------
WITH prefixes(p) AS (
  VALUES ('bria'),('char'),('dani'),('emil'),('fran'),
         ('gabr'),('hele'),('isab'),('jose'),('kira')
),
to_insert AS (
  SELECT p, i FROM prefixes, generate_series(1,5) AS i
)
INSERT INTO users (google_id, email, username)
SELECT 'seed_' || p || i, p || i || '@seed.local', p || i
FROM to_insert
ON CONFLICT (username) DO NOTHING;

-- ---------- 10 communities (bria1 as creator) ----------
INSERT INTO communities (name, description, creator_id)
SELECT name, descr, (SELECT id FROM users WHERE username = 'bria1')
FROM (VALUES
  ('askreddit',  'Open-ended questions and stories.'),
  ('programming','Software, languages, and tools.'),
  ('gaming',     'Video games and the people who play them.'),
  ('news',       'World, tech, and culture news.'),
  ('science',    'Discoveries, papers, and physics arguments.'),
  ('movies',     'Films, recommendations, and hot takes.'),
  ('books',      'Reading recommendations and discussion.'),
  ('food',       'Cooking, recipes, and gear.'),
  ('travel',     'Trip reports and travel hacks.'),
  ('fitness',    'Lifting, running, and the long road.')
) AS t(name, descr)
ON CONFLICT (name) DO NOTHING;

-- ---------- Everyone joins everything ----------
INSERT INTO memberships (community_id, user_id)
SELECT c.id, u.id
FROM communities c, users u
WHERE u.username ~ '^(bria|char|dani|emil|fran|gabr|hele|isab|jose|kira)[0-9]+$'
ON CONFLICT DO NOTHING;

-- ---------- 100 posts (10 per community) ----------
WITH titles_per_community(cname, titles) AS (
  VALUES
    ('askreddit', ARRAY[
      'What is the most useless skill you have?',
      'What is something you learned embarrassingly late?',
      'What is the best advice you ever received?',
      'What is the strangest dream you can remember?',
      'What is a random fact that lives rent-free in your head?',
      'What is your favorite cheap meal?',
      'What is your most controversial food opinion?',
      'What movie changed the way you think?',
      'What is the worst job you have ever had?',
      'What city is the most overrated?'
    ]),
    ('programming', ARRAY[
      'TIL about Postgres CTEs and now I cannot stop using them',
      'Switched from VS Code to Neovim — what am I missing?',
      'Best resources to learn Rust in 2026?',
      'Why does everyone hate JavaScript?',
      'SQL window functions changed how I think about queries',
      'What is your actual day-to-day git workflow?',
      'Spent 3 days debugging a timezone bug. Lessons learned.',
      'Building my first compiler — going better than expected',
      'Most useful CLI tool you discovered last year?',
      'Do AI assistants make you a worse engineer?'
    ]),
    ('gaming', ARRAY[
      'Just finished Elden Ring DLC, what should I play next?',
      'Steam Deck OLED is the best purchase I made in years',
      'Why are AAA games getting worse?',
      'Indie devs are carrying the industry',
      'Hot take: open-world fatigue is real',
      'Best co-op games to play with a non-gamer partner?',
      'Replayed Skyrim, the world still holds up',
      'Any good Soulslikes I might have missed?',
      'Multiplayer game etiquette is dead',
      'What game has the best soundtrack of all time?'
    ]),
    ('news', ARRAY[
      'Major breakthrough in fusion energy announced',
      'Tech layoffs continue into Q2',
      'New climate report sparks debate',
      'AI regulation moving faster than expected in EU',
      'Global semiconductor supply chain shifts again',
      'Mars rover sends back unexpected data',
      'Cybersecurity bill introduced in US Congress',
      'Electric vehicle sales surge worldwide',
      'New social media platform gains real traction',
      'Quantum computing milestone reached'
    ]),
    ('science', ARRAY[
      'New evidence about dark matter has scientists puzzled',
      'Octopuses pass mirror test in new study',
      'Mars sample return mission update',
      'Why are we still arguing about Pluto?',
      'Coolest physics experiment you have heard of?',
      'Just read about CRISPR and my mind is blown',
      'James Webb keeps surprising astronomers',
      'Mathematicians prove a longstanding conjecture',
      'What is the best science book you have read?',
      'Antibiotic resistance is a bigger problem than people realize'
    ]),
    ('movies', ARRAY[
      'Just watched Oppenheimer for the third time, still incredible',
      'Underrated 90s movies that deserve more love?',
      'Why is Hollywood so obsessed with remakes?',
      'Best movie endings of all time?',
      'Just discovered Studio Ghibli — where do I start?',
      'Films that aged better than expected',
      'Worst Best Picture winner?',
      'Christopher Nolan ranked worst to best',
      'The movie theater experience is dying',
      'What is your comfort movie?'
    ]),
    ('books', ARRAY[
      'Just finished Project Hail Mary — what next?',
      'Underrated sci-fi recommendations?',
      'Why does no one talk about Le Guin?',
      'Best non-fiction you read this year?',
      'Audiobooks vs paper — discuss',
      'Fantasy series that gets better past book 3?',
      'Started Brandon Sanderson, I am 800 pages deep',
      'Books that changed how you think',
      'Most overrated classic novel?',
      'What book do you wish more people read?'
    ]),
    ('food', ARRAY[
      'Quickest weeknight dinner that does not feel sad?',
      'Sourdough is harder than YouTube made it look',
      'Best knife under $100?',
      'Cast iron care — am I doing this wrong?',
      'Cheapest meal you actually enjoy?',
      'Why did no one tell me about miso paste sooner?',
      'Best home espresso setup under $500?',
      'Pickling for beginners — where do I start?',
      'Taco Bell breakfast is underrated',
      'Pasta shape tier list'
    ]),
    ('travel', ARRAY[
      'Solo trip to Japan, three weeks, what should I not miss?',
      'Hidden gems in Southeast Asia',
      'Best travel credit card in 2026?',
      'Eurail pass worth it in 2026?',
      'Mexico City exceeded every expectation',
      'Why is travel so much more crowded than 5 years ago?',
      'Travel hacks that actually save money',
      'Underrated US national parks?',
      'Worst tourist trap you fell for?',
      'Just got back from Portugal — here is my itinerary'
    ]),
    ('fitness', ARRAY[
      'Six months of consistent lifting, finally seeing results',
      'Best home gym setup under $1000?',
      'Cardio I actually enjoy',
      'How do you stay motivated past day 90?',
      'Creatine — overrated or essential?',
      'Just ran my first half marathon',
      'Bodyweight-only workouts that actually work',
      'Calorie counting changed my life',
      'Best stretch for desk workers?',
      'Cutting vs maintaining — which is harder?'
    ])
),
expanded AS (
  SELECT c.id AS community_id, t.title
  FROM titles_per_community tpc
  JOIN communities c ON c.name = tpc.cname
  CROSS JOIN LATERAL unnest(tpc.titles) AS t(title)
)
INSERT INTO posts (community_id, author_id, kind, title, body, ups, downs)
SELECT
  e.community_id,
  (SELECT id FROM users
    WHERE username ~ '^(bria|char|dani|emil|fran|gabr|hele|isab|jose|kira)[0-9]+$'
    ORDER BY random() LIMIT 1),
  'text'::post_kind,
  e.title,
  'Curious what folks here think. Drop your take in the comments — interested in counter-arguments too.',
  (random()*120)::int,
  (random()*20)::int
FROM expanded e;

-- ---------- 3 top-level comments per post ----------
WITH bodies AS (
  SELECT unnest(ARRAY[
    'This is exactly what I needed to read today.',
    'Great post, thanks for sharing.',
    'Had the same experience last year. You are not alone.',
    'Strongly disagree, but I respect the take.',
    'Saving this for later.',
    'Source? Genuinely curious where you read this.',
    'Tried something similar last week — can confirm it works.',
    'Underrated take, surprised by the downvotes.',
    'This deserves more visibility.',
    'Where can I read more about this?',
    'Been there. It gets better.',
    'Counter-argument: the opposite has also been true for me.',
    'Came here to say this — you beat me to it.',
    'Best thread I have seen on this sub all month.',
    'Following for the answers in the comments.',
    'Idk, feels overstated. Anyone else feel that way?',
    'Hot take but I agree with every word.',
    'Did not expect to relate this hard.',
    'OP, what made you finally pull the trigger?',
    'I have heard the opposite from people I trust — anyone have data?'
  ]) AS body
)
INSERT INTO comments (post_id, author_id, body)
SELECT
  p.id,
  (SELECT id FROM users
    WHERE username ~ '^(bria|char|dani|emil|fran|gabr|hele|isab|jose|kira)[0-9]+$'
    ORDER BY random() LIMIT 1),
  (SELECT body FROM bodies ORDER BY random() LIMIT 1)
FROM posts p,
     LATERAL generate_series(1, 3) AS g(i)
WHERE p.created_at >= NOW() - INTERVAL '1 minute';  -- only seed posts

-- ---------- 1 threaded reply per post ----------
WITH replies AS (
  SELECT unnest(ARRAY[
    'Fair point, but consider the edge case.',
    'Exactly this — saved me hours.',
    'Has not been my experience, but YMMV.',
    'Wait, can you expand on this?',
    'Big +1 from me.',
    'Disagree on the specifics, agree on the conclusion.',
    'I think you are underselling how hard this is.',
    'Right answer, wrong reasoning, but right answer.',
    'This is the energy I come to Reddit for.',
    'OP if you read this, I owe you a beer.'
  ]) AS body
),
roots AS (
  SELECT DISTINCT ON (post_id) id, post_id
  FROM comments
  WHERE parent_id IS NULL
  ORDER BY post_id, random()
)
INSERT INTO comments (post_id, parent_id, author_id, body)
SELECT
  r.post_id,
  r.id,
  (SELECT id FROM users
    WHERE username ~ '^(bria|char|dani|emil|fran|gabr|hele|isab|jose|kira)[0-9]+$'
    ORDER BY random() LIMIT 1),
  (SELECT body FROM replies ORDER BY random() LIMIT 1)
FROM roots r;

COMMIT;

-- ---------- Sanity check ----------
SELECT
  (SELECT COUNT(*) FROM users     WHERE username ~ '^(bria|char|dani|emil|fran|gabr|hele|isab|jose|kira)[0-9]+$') AS seed_users,
  (SELECT COUNT(*) FROM communities) AS communities,
  (SELECT COUNT(*) FROM posts)       AS posts,
  (SELECT COUNT(*) FROM comments)    AS comments;
