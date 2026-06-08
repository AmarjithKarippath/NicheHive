-- +goose Up
-- +goose StatementBegin
-- ============================================================
-- Seed data: 50 users, 10 communities, 100 posts, 300 comments.
-- Idempotent: skips rows that already exist (ON CONFLICT for unique
-- tables; existence guard for posts/comments).
-- ============================================================

-- ---------- 50 seed users (10 prefixes x 5) ----------
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

-- ---------- 10 seed communities (creator: bria1) ----------
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

-- ---------- everyone joins everything ----------
INSERT INTO memberships (community_id, user_id)
SELECT c.id, u.id
FROM communities c, users u
WHERE u.username ~ '^(bria|char|dani|emil|fran|gabr|hele|isab|jose|kira)[0-9]+$'
  AND c.name IN ('askreddit','programming','gaming','news','science',
                 'movies','books','food','travel','fitness')
ON CONFLICT DO NOTHING;

-- ---------- 100 seed posts (10 per community) ----------
-- Guarded: skips if any post already exists in the askreddit community.
WITH titles_per_community(cname, titles) AS (VALUES
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
  'Curious what folks here think. Drop your take in the comments — counter-arguments welcome.',
  (random()*120)::int,
  (random()*20)::int
FROM expanded e
WHERE NOT EXISTS (
  SELECT 1 FROM posts p
  JOIN communities c ON c.id = p.community_id
  WHERE c.name = 'askreddit'
);

-- ---------- 300 topic-relevant comments (3 per post) ----------
-- Guarded the same way — only inserts if no comments exist on a seeded post.
WITH per_post(title, comments) AS (VALUES
  ($$What is the most useless skill you have?$$::text, ARRAY[
    $$Can recite the alphabet backwards in 4 seconds. Came up exactly once at a bar.$$,
    $$Naming every Pokemon from Gen 1 in order. Wife remains unimpressed.$$,
    $$Tying a cherry stem with my tongue. Peaked sophomore year.$$
  ]::text[]),
  ($$What is something you learned embarrassingly late?$$, ARRAY[
    $$That tomato is botanically a fruit. Took me until age 23.$$,
    $$How to properly hold chopsticks. Coworker very patient with 31-year-old me.$$,
    $$Salting pasta water. My pasta life is divided into Before and After.$$
  ]),
  ($$What is the best advice you ever received?$$, ARRAY[
    $$If you would not move toward it, do not stay in it. Career defining.$$,
    $$Boring decisions, exciting life. Stole it from a CEO and never regretted.$$,
    $$Always tip 20, always over-prepare, always leave 10 minutes early.$$
  ]),
  ($$What is the strangest dream you can remember?$$, ARRAY[
    $$Was a sentient toaster making small talk with a fridge about geopolitics.$$,
    $$Won an Oscar for a movie I had never seen. Acceptance speech was about turtles.$$,
    $$My dog explained taxes to me in perfect English. Apparently I owe back taxes.$$
  ]),
  ($$What is a random fact that lives rent-free in your head?$$, ARRAY[
    $$Bananas are berries, strawberries are not. Botanists are messing with us.$$,
    $$Honey never spoils. Edible honey has been pulled from Egyptian tombs.$$,
    $$Octopuses have three hearts and blue blood. Aliens have been here the whole time.$$
  ]),
  ($$What is your favorite cheap meal?$$, ARRAY[
    $$Rice + frozen veg + egg + soy sauce + chili crisp. Done in six minutes.$$,
    $$Lentil soup with crusty bread. Costs nothing, eats like a Sunday.$$,
    $$Toasted PB and J with banana slices on a panini press. Try it once.$$
  ]),
  ($$What is your most controversial food opinion?$$, ARRAY[
    $$Mustard belongs on pizza. Hill I will die on.$$,
    $$Brown butter beats truffle. Truffle is overhyped almost everywhere it appears.$$,
    $$Microwaved leftover pasta tastes better than fresh pasta. Send the hate.$$
  ]),
  ($$What movie changed the way you think?$$, ARRAY[
    $$Arrival. Made me realize language shapes time perception.$$,
    $$Mr. Nobody. Spent a week thinking about decisions and parallel lives.$$,
    $$Persepolis. Made history personal in a way no textbook ever did.$$
  ]),
  ($$What is the worst job you have ever had?$$, ARRAY[
    $$Door-to-door knife sales as a teenager. Cried in more than one driveway.$$,
    $$Overnight call center 11p-7a. My circadian rhythm never recovered.$$,
    $$Stadium hot dog vendor. Smelled like onions for an entire summer.$$
  ]),
  ($$What city is the most overrated?$$, ARRAY[
    $$Vegas. Novelty wears off in 36 hours and you still have three days left.$$,
    $$LA. Traffic erases every nice thing about it within a week.$$,
    $$Paris. Beautiful, but the gap between expectation and reality is brutal.$$
  ]),
  ($$TIL about Postgres CTEs and now I cannot stop using them$$, ARRAY[
    $$Wait until you discover MATERIALIZED. You will fall in love a second time.$$,
    $$Recursive CTEs are the moment SQL starts to feel like a real language.$$,
    $$Be careful with nested CTEs and no index plan. Looks elegant, scans the world.$$
  ]),
  ($$Switched from VS Code to Neovim — what am I missing?$$, ARRAY[
    $$LSP setup is 80 percent of the work. Once configured, the experience is incredible.$$,
    $$Most of the productivity boost is muscle memory, not the editor.$$,
    $$Honest answer: I learned I was a worse touch typist than I thought.$$
  ]),
  ($$Best resources to learn Rust in 2026?$$, ARRAY[
    $$The Rust Book + Rustlings remains the gold path. Do not skip the exercises.$$,
    $$Jon Gjengset on YouTube. Eight hours of him teaches more than eight weeks of tutorials.$$,
    $$Build a TCP server from scratch. The borrow checker will roast you until you understand it.$$
  ]),
  ($$Why does everyone hate JavaScript?$$, ARRAY[
    $$People do not hate JS, they hate the ecosystem treadmill.$$,
    $$Decent language stuck with a worse runtime story than every other modern language.$$,
    $$Type coercion. Equality. NaN. We have been wronged.$$
  ]),
  ($$SQL window functions changed how I think about queries$$, ARRAY[
    $$ROW_NUMBER() OVER (PARTITION BY ...) replaced 80 percent of my self joins.$$,
    $$LAG and LEAD changed how I think about time series data.$$,
    $$Once you grok the frame clause, everything else clicks.$$
  ]),
  ($$What is your actual day-to-day git workflow?$$, ARRAY[
    $$Trunk based, feature flags, small PRs. Rebase before merging.$$,
    $$I keep a scratch branch called junk for half-formed experiments. Saves me weekly.$$,
    $$Honestly: stash, fetch, rebase, push, repeat. Boring is the point.$$
  ]),
  ($$Spent 3 days debugging a timezone bug. Lessons learned.$$, ARRAY[
    $$I now refuse to store anything except UTC. Display layer does the math.$$,
    $$Postgres timestamptz is a lie unless you set the session TZ explicitly.$$,
    $$Real lesson: every timezone bug is actually an assumption bug.$$
  ]),
  ($$Building my first compiler — going better than expected$$, ARRAY[
    $$Crafting Interpreters by Nystrom is the book. Read it twice.$$,
    $$Wait until you hit register allocation. The dragon book starts making sense fast.$$,
    $$Wrote a Lisp compiler last summer and it broke my brain in the best way.$$
  ]),
  ($$Most useful CLI tool you discovered last year?$$, ARRAY[
    $$ripgrep. Once you start using rg you cannot go back to grep.$$,
    $$fzf. Piped into git checkout or kubectl exec, it is a superpower.$$,
    $$lazygit. Made me stop pretending I knew git from the command line.$$
  ]),
  ($$Do AI assistants make you a worse engineer?$$, ARRAY[
    $$Only if you let them. As autocomplete: meh. As a rubber duck: amazing.$$,
    $$Juniors skipping fundamentals is the real risk. I see it weekly.$$,
    $$Made me write more, debug less, and read code I did not understand. Net positive.$$
  ]),
  ($$Just finished Elden Ring DLC, what should I play next?$$, ARRAY[
    $$Sekiro. Different vibe but scratches the same itch.$$,
    $$Lies of P is genuinely great. Souls adjacent and underrated.$$,
    $$Hollow Knight now, Silksong when it finally drops.$$
  ]),
  ($$Steam Deck OLED is the best purchase I made in years$$, ARRAY[
    $$Best handheld since the GBA SP. PC handhelds are the future.$$,
    $$Battery life with the OLED is the actual game changer for me.$$,
    $$I am finishing a 10 year Steam backlog. That says everything.$$
  ]),
  ($$Why are AAA games getting worse?$$, ARRAY[
    $$Live service ate the industry. Single player budgets compete with seasonal monetization.$$,
    $$Risk aversion. Every project under 50M gets cancelled.$$,
    $$Three years of development chasing trends that died in year two.$$
  ]),
  ($$Indie devs are carrying the industry$$, ARRAY[
    $$Hades, Stardew, Hollow Knight, Balatro. None came from a publisher pitch deck.$$,
    $$Four-person indie teams ship 30 hours of banger. AAA needs 4000 to ship 30 hours of cutscenes.$$,
    $$Best gaming moments of the decade for me have all been indie. Easily.$$
  ]),
  ($$Hot take: open-world fatigue is real$$, ARRAY[
    $$Yes. I cannot do another climb the tower to reveal the map game.$$,
    $$Game design forgot that big is not the same as good.$$,
    $$Give me a tight 15 hour linear masterpiece over 80 hours of busywork.$$
  ]),
  ($$Best co-op games to play with a non-gamer partner?$$, ARRAY[
    $$It Takes Two. Designed for exactly this purpose and it works.$$,
    $$Overcooked 2. Tested our relationship and reflexes simultaneously.$$,
    $$Unravel Two. Mellow, gorgeous, forgiving.$$
  ]),
  ($$Replayed Skyrim, the world still holds up$$, ARRAY[
    $$The world has never been topped. The combat has always been mid.$$,
    $$Best advertisement Bethesda ever ran for modding.$$,
    $$Try Anniversary Edition with Survival Mode on. Whole new game.$$
  ]),
  ($$Any good Soulslikes I might have missed?$$, ARRAY[
    $$Nioh 2. Best combat in any Soulslike full stop.$$,
    $$Remnant 2 if you want a gun-focused take.$$,
    $$Lords of the Fallen 2023 is messy but the dual realm gimmick is cool.$$
  ]),
  ($$Multiplayer game etiquette is dead$$, ARRAY[
    $$Voice chat is unusable. Ten minutes of CoD ruined my week.$$,
    $$The good lobbies still exist. You have to build a Discord and curate them.$$,
    $$Old MMOs had community because servers were small and reputation mattered.$$
  ]),
  ($$What game has the best soundtrack of all time?$$, ARRAY[
    $$Nier Automata. Easy. Weight of the World still hits.$$,
    $$Chrono Trigger. Mitsuda and Uematsu and nothing else needs saying.$$,
    $$Outer Wilds. The way the score reveals what is happening is masterful.$$
  ]),
  ($$Major breakthrough in fusion energy announced$$, ARRAY[
    $$Net energy gain is real now. Scaling to grid is the next 30 years.$$,
    $$Headlines always undersell the engineering gap between lab and grid.$$,
    $$Helion is interesting but everyone is overpromising timelines as usual.$$
  ]),
  ($$Tech layoffs continue into Q2$$, ARRAY[
    $$Over-hiring 2021-22 is finally fully unwinding. Painful but expected.$$,
    $$Mid level ICs hit hardest. Juniors gone, seniors safe-ish, middle gets the squeeze.$$,
    $$AI is the polite excuse. The unsaid one is interest rates.$$
  ]),
  ($$New climate report sparks debate$$, ARRAY[
    $$Less debate, more policy. We are debating physics at this point.$$,
    $$Adaptation funding matters more than arguments about whether to act.$$,
    $$Genuinely curious who is left to convince at this point.$$
  ]),
  ($$AI regulation moving faster than expected in EU$$, ARRAY[
    $$GDPR sequel energy. Brussels effect will pull the US along eventually.$$,
    $$Devil is in implementation. The high-risk categorization is ambiguous.$$,
    $$Compliance teams are about to be the highest paid people at every tech company.$$
  ]),
  ($$Global semiconductor supply chain shifts again$$, ARRAY[
    $$Taiwan concentration is the real story everyone is dancing around.$$,
    $$CHIPS Act money is finally hitting fabs. Results show up in 2027-28.$$,
    $$Skilled labor shortage is going to be a worse bottleneck than capital.$$
  ]),
  ($$Mars rover sends back unexpected data$$, ARRAY[
    $$The methane signal has been weird for years. Could be geology, could be biology.$$,
    $$Sample return cannot come soon enough.$$,
    $$Love that unexpected on Mars almost always means slightly wetter than expected.$$
  ]),
  ($$Cybersecurity bill introduced in US Congress$$, ARRAY[
    $$Mandatory breach disclosure under 72 hours will hurt vendors that have been hiding.$$,
    $$Once the SEC started enforcing 8-K rules, the writing was on the wall.$$,
    $$Needs real teeth or it joins the pile of well-intentioned cyber bills.$$
  ]),
  ($$Electric vehicle sales surge worldwide$$, ARRAY[
    $$Chinese OEMs are eating everyone lunch on cost and feature parity.$$,
    $$Charging infrastructure is still the gating factor in the US specifically.$$,
    $$Used EV market is finally hitting price points that bring in normal buyers.$$
  ]),
  ($$New social media platform gains real traction$$, ARRAY[
    $$The cycle is exhausting. Twitter, Mastodon, Bluesky, Threads, what is next?$$,
    $$Network effects are sticky. Most of these fizzle when novelty wears off.$$,
    $$I just want a chronological feed from people I follow. Why is that hard?$$
  ]),
  ($$Quantum computing milestone reached$$, ARRAY[
    $$Milestone is doing a lot of work in that sentence. Read the paper, it is modest progress.$$,
    $$Error correction is the actual bottleneck and nothing about it is solved.$$,
    $$Hype cycle plus real progress. Hard to tell which is moving the needle.$$
  ]),
  ($$New evidence about dark matter has scientists puzzled$$, ARRAY[
    $$The MOND vs particle DM debate is heating up again. Exciting time to be a cosmologist.$$,
    $$Every few years a new anomaly reopens this argument. Never disappointing.$$,
    $$If it turns out to be modified gravity, half the field needs new careers.$$
  ]),
  ($$Octopuses pass mirror test in new study$$, ARRAY[
    $$Octopus intelligence keeps undermining everything we thought about cephalopod cognition.$$,
    $$I will never look at calamari the same way again.$$,
    $$If they lived longer than four years they would have built a civilization.$$
  ]),
  ($$Mars sample return mission update$$, ARRAY[
    $$Most exciting space science of the decade. We are about to do alien-rock geology.$$,
    $$Budget overruns are insane. NASA cannot keep doing flagship missions this way.$$,
    $$ESA stepping in could be the only thing that saves the timeline.$$
  ]),
  ($$Why are we still arguing about Pluto?$$, ARRAY[
    $$It is a fascinating body. Calling it a planet or not does not change that.$$,
    $$The IAU definition is bad. Dynamical balance excludes Mercury near a Mercury sized star.$$,
    $$Pluto is a planet emotionally and that is enough for me.$$
  ]),
  ($$Coolest physics experiment you have heard of?$$, ARRAY[
    $$Bell tests. The fact that reality is non-local still messes with my head.$$,
    $$Aharonov-Bohm. Quantum effects from a field you never touched. Wild.$$,
    $$Hafele-Keating with atomic clocks on commercial flights. Casual relativity.$$
  ]),
  ($$Just read about CRISPR and my mind is blown$$, ARRAY[
    $$Wait until you read about base editing and prime editing. CRISPR is already kind of obsolete.$$,
    $$The germline ethical debate is going to define biology this decade.$$,
    $$Practically: medical applications are running ahead of regulatory frameworks.$$
  ]),
  ($$James Webb keeps surprising astronomers$$, ARRAY[
    $$The early-galaxy data is breaking models that everyone was comfortable with.$$,
    $$We did not expect mature dust at z=10. Now we have to explain it.$$,
    $$Best 10 billion dollars humanity ever spent on a single instrument.$$
  ]),
  ($$Mathematicians prove a longstanding conjecture$$, ARRAY[
    $$Source the proof. Three false alarms in five years on this conjecture.$$,
    $$Beautiful work if it holds. Combinatorics is having a moment.$$,
    $$Read the arxiv paper. The technique generalizes to adjacent problems.$$
  ]),
  ($$What is the best science book you have read?$$, ARRAY[
    $$Thing Explainer by Munroe. Deep concepts with limited vocabulary. Brilliant.$$,
    $$Godel, Escher, Bach. Took me three tries but worth it.$$,
    $$Sapiens. Pop sci yes, but it reframed how I think about agriculture and money.$$
  ]),
  ($$Antibiotic resistance is a bigger problem than people realize$$, ARRAY[
    $$Pipeline of new antibiotics is empty. Real trouble in 20 years.$$,
    $$Phage therapy is getting clinical attention again. Long overdue.$$,
    $$Every vet prescribing without culture is contributing to the problem.$$
  ]),
  ($$Just watched Oppenheimer for the third time, still incredible$$, ARRAY[
    $$The Pugh-Murphy interrogation scene is one of the best in 10 years.$$,
    $$First Nolan movie that landed emotionally for me. Tenet broke me on him for a while.$$,
    $$Three viewings and I still cannot pick a favorite scene.$$
  ]),
  ($$Underrated 90s movies that deserve more love?$$, ARRAY[
    $$Fallen with Denzel. Slow burn, perfect ending. Never comes up.$$,
    $$Dark City. Came out a few months before Matrix and did half the same things first.$$,
    $$Galaxy Quest. Aged better than any other 90s sci-fi comedy.$$
  ]),
  ($$Why is Hollywood so obsessed with remakes?$$, ARRAY[
    $$IP risk is lower than the cost of a marketing department for a new title.$$,
    $$Audiences keep showing up. Studios are being rational here.$$,
    $$Theatrical demand collapsed for mid-budget originals. Remakes survive theaters, originals go to streaming.$$
  ]),
  ($$Best movie endings of all time?$$, ARRAY[
    $$Whiplash. The last 10 minutes are a complete movie on their own.$$,
    $$Prisoners. That tap. Cuts to black. Perfect.$$,
    $$Burn After Reading. The Coens not bothering to explain anything is the joke.$$
  ]),
  ($$Just discovered Studio Ghibli — where do I start?$$, ARRAY[
    $$Start with Totoro, then Spirited Away. Save Princess Mononoke for week three.$$,
    $$Whisper of the Heart. Underrated and probably the most personal one.$$,
    $$Watch them in release order. The artistic evolution is most of the experience.$$
  ]),
  ($$Films that aged better than expected$$, ARRAY[
    $$Children of Men. Year by year it looks more like documentary than fiction.$$,
    $$Office Space. Gets funnier every time you re-enter the workforce.$$,
    $$The Truman Show. Basically a documentary about social media now.$$
  ]),
  ($$Worst Best Picture winner?$$, ARRAY[
    $$Crash (2004). Still cannot believe.$$,
    $$Green Book. Fine movie, terrible Best Picture over Roma.$$,
    $$Forrest Gump beating Pulp Fiction is a war crime.$$
  ]),
  ($$Christopher Nolan ranked worst to best$$, ARRAY[
    $$Tenet bottom, Oppenheimer top. The middle is interchangeable depending on mood.$$,
    $$Memento has aged best. Watch it twice in a row, you will see new things.$$,
    $$Insomnia is consistently underrated in these rankings.$$
  ]),
  ($$The movie theater experience is dying$$, ARRAY[
    $$IMAX 70mm is the only thing that gets me out of the house anymore.$$,
    $$Drafthouse style chains are the only ones doing it right. Loud chewing should be illegal.$$,
    $$Phones being unenforceable killed it for me two years ago.$$
  ]),
  ($$What is your comfort movie?$$, ARRAY[
    $$About Time. Cry every time. Recommend to friends going through it.$$,
    $$Big Lebowski. Smells like a Saturday afternoon.$$,
    $$The Holiday. Predictable, charming, full Christmas in July energy.$$
  ]),
  ($$Just finished Project Hail Mary — what next?$$, ARRAY[
    $$Recursion by Crouch. Pacing similar and just as cinematic.$$,
    $$Children of Time. Different vibe but the alien POV will scratch the itch.$$,
    $$The Martian if you have not read Weir's first one. Better than the movie.$$
  ]),
  ($$Underrated sci-fi recommendations?$$, ARRAY[
    $$Greg Egan. Permutation City is hard to read and impossible to forget.$$,
    $$Doomsday Book by Connie Willis. Time travel + Black Death + heartbreak.$$,
    $$Blindsight by Peter Watts. The vampire footnote alone makes it worth it.$$
  ]),
  ($$Why does no one talk about Le Guin?$$, ARRAY[
    $$Left Hand of Darkness should be required reading. Period.$$,
    $$She is quietly cited as the influence for everyone in modern SFF for 40 years.$$,
    $$Dispossessed remade my political brain when I was 19.$$
  ]),
  ($$Best non-fiction you read this year?$$, ARRAY[
    $$Empire of Pain. Sackler family and Purdue. Furious for 400 pages.$$,
    $$Chip War by Miller. Reframed how I think about geopolitics.$$,
    $$How to Win Friends and Influence People. Cringey title, surprisingly real.$$
  ]),
  ($$Audiobooks vs paper — discuss$$, ARRAY[
    $$Audiobook for memoir and pop sci. Paper for fiction. Different mediums for me.$$,
    $$I retain way less from audio. Worth knowing your own brain.$$,
    $$Audiobook + paperback on the same book is the cheat code. Try it.$$
  ]),
  ($$Fantasy series that gets better past book 3?$$, ARRAY[
    $$Malazan. First two are rough, books 3-10 are some of the best fantasy ever written.$$,
    $$Stormlight Archive. Each book is bigger and better. Tolkien scale ambition.$$,
    $$Realm of the Elderlings. Robin Hobb is criminally under-read.$$
  ]),
  ($$Started Brandon Sanderson, I am 800 pages deep$$, ARRAY[
    $$You are in for a treat. Mistborn first trilogy is the cleanest onboarding.$$,
    $$Wait until you hit Stormlight book 3. The avalanche pages are unforgettable.$$,
    $$Do not burn out. Read something short between cosmere books or it gets samey.$$
  ]),
  ($$Books that changed how you think$$, ARRAY[
    $$Sapiens. Cliche answer for a reason.$$,
    $$Thinking Fast and Slow. Made me distrust my own intuition in a useful way.$$,
    $$Mans Search for Meaning. Re-read every couple years, lands differently each time.$$
  ]),
  ($$Most overrated classic novel?$$, ARRAY[
    $$Catcher in the Rye. Tried at 15 and at 30. Holden remains insufferable.$$,
    $$On the Road. Boring road trip plus prose that thinks it is profound.$$,
    $$Wuthering Heights. Everyone is awful. The book wants you to find it romantic.$$
  ]),
  ($$What book do you wish more people read?$$, ARRAY[
    $$House of Leaves. Genuinely a new form of book, not just a story.$$,
    $$The Master and Margarita. Best opening chapter in 20th century literature.$$,
    $$Stoner by John Williams. Quiet, devastating, perfect novel.$$
  ]),
  ($$Quickest weeknight dinner that does not feel sad?$$, ARRAY[
    $$Marry me chicken in one pan. 25 minutes, tastes like Saturday.$$,
    $$Black beans + rice + lime + avocado + pickled onion. 12 minutes, real meal.$$,
    $$Ramen with frozen dumplings + bok choy + chili crisp. Levels up instant noodles.$$
  ]),
  ($$Sourdough is harder than YouTube made it look$$, ARRAY[
    $$Hydration math kills most people. Stay under 75 percent until your starter is dialed.$$,
    $$Tartine method, dutch oven, 500F, lid on 20, lid off 20. Whole recipe.$$,
    $$The real curve is reading your starter, not the timer. Took me four months.$$
  ]),
  ($$Best knife under $100?$$, ARRAY[
    $$Tojiro DP 8 inch. Sub 80 dollars and the gateway to Japanese knives.$$,
    $$Victorinox Fibrox 8 inch chef. 40 dollars and still in my drawer after a decade.$$,
    $$Mac HB-85 if you want something a bit fancier.$$
  ]),
  ($$Cast iron care — am I doing this wrong?$$, ARRAY[
    $$Just cook in it. Skip the over-engineered seasoning routines.$$,
    $$Wash with soap. Modern soap will not strip a properly seasoned pan. Internet lied.$$,
    $$Dry over heat after washing, thin layer of oil. That is it.$$
  ]),
  ($$Cheapest meal you actually enjoy?$$, ARRAY[
    $$Beans and rice. Add a fried egg, you are cooking.$$,
    $$Egg fried rice. Day old rice + soy + egg + scallion. Cheap, fast, satisfying.$$,
    $$Aglio e olio. Six ingredients, five star meal, four bucks.$$
  ]),
  ($$Why did no one tell me about miso paste sooner?$$, ARRAY[
    $$Try a teaspoon in caramel. Unfair how good it is.$$,
    $$Stir into mashed potatoes instead of cream. Trust me.$$,
    $$Miso butter on a steak. Try once and it is in your weekly rotation.$$
  ]),
  ($$Best home espresso setup under $500?$$, ARRAY[
    $$Gaggia Classic Pro + Eureka Mignon Specialita. Cafe quality at home.$$,
    $$Breville Bambino Plus + Baratza Encore ESP. Newer setup, less faff.$$,
    $$Manual: Flair 58 + Eureka. Different vibe, ridiculous quality for the money.$$
  ]),
  ($$Pickling for beginners — where do I start?$$, ARRAY[
    $$Refrigerator pickles first. Cucumber + vinegar + sugar + dill. Eat in 48 hours.$$,
    $$Quick pickled red onion belongs on every taco for the rest of your life.$$,
    $$Once you do brine fermentation you stop buying jarred. Salt brine + cabbage. Done.$$
  ]),
  ($$Taco Bell breakfast is underrated$$, ARRAY[
    $$Breakfast crunchwrap is genuinely great fast food. Not even joking.$$,
    $$Their potato bites are unfairly good for the price.$$,
    $$I rank it above McDonalds breakfast in everything but biscuits.$$
  ]),
  ($$Pasta shape tier list$$, ARRAY[
    $$S tier: rigatoni. Picks up sauce, holds bite, idiot proof. Discussion over.$$,
    $$Tagliatelle with bolognese is the only correct answer. Spaghetti is a marketing choice.$$,
    $$Orecchiette + sausage + broccoli rabe is the most underrated pairing in pasta.$$
  ]),
  ($$Solo trip to Japan, three weeks, what should I not miss?$$, ARRAY[
    $$Get out of Tokyo by week two. Naoshima, Koya-san, Kanazawa. Real Japan starts there.$$,
    $$JR Pass math has changed in 2026. Recheck before buying. Often not worth it now.$$,
    $$Onsen night in Hakone or Kusatsu. Single best evening of my whole trip.$$
  ]),
  ($$Hidden gems in Southeast Asia$$, ARRAY[
    $$Phong Nha in Vietnam. Caves are unreal, tourist load is still low.$$,
    $$Hsipaw in Myanmar (when politics allow) for the trek to Pankam village.$$,
    $$Koh Lanta over Phuket. Less polished, more soul.$$
  ]),
  ($$Best travel credit card in 2026?$$, ARRAY[
    $$Chase Sapphire Reserve still strong if you actually use the credits.$$,
    $$Amex Platinum if you fly Delta and care about lounges.$$,
    $$Capital One Venture X is the best no-brainer card right now.$$
  ]),
  ($$Eurail pass worth it in 2026?$$, ARRAY[
    $$Math has shifted. Point to point is often cheaper if you book ahead.$$,
    $$Worth it only if you are doing 5+ countries in two weeks.$$,
    $$Always do a dry run on Trainline before buying the pass.$$
  ]),
  ($$Mexico City exceeded every expectation$$, ARRAY[
    $$It is the food capital of the western hemisphere and not enough people say it.$$,
    $$Get out to Teotihuacan at sunrise. Clears most tourists, magical.$$,
    $$Roma Norte for first timers, Coyoacan if you have a second trip.$$
  ]),
  ($$Why is travel so much more crowded than 5 years ago?$$, ARRAY[
    $$Instagram homogenized every bucket list. Top 50 spots got 100x worse.$$,
    $$Off season is the cheat code. Same place, half the people.$$,
    $$I now plan trips around what is NOT in the top 50 Google results.$$
  ]),
  ($$Travel hacks that actually save money$$, ARRAY[
    $$Stopover programs (Iceland, Portugal, Singapore) get you two cities for one flight.$$,
    $$Hotel direct + lowest rate guarantee email. Works more often than people think.$$,
    $$Eat dinner at lunch prices. Most countries have a menu del dia equivalent at midday.$$
  ]),
  ($$Underrated US national parks?$$, ARRAY[
    $$Great Basin. Bristlecone pines and Lehman Caves. Almost nobody there.$$,
    $$North Cascades. Sits next to its famous neighbors and stays empty.$$,
    $$Isle Royale. Hardest to get to, most rewarding.$$
  ]),
  ($$Worst tourist trap you fell for?$$, ARRAY[
    $$Mona Lisa. Crowd is the experience, painting is not. Brutal.$$,
    $$Hollywood Walk of Fame. Even by trap standards it underperforms.$$,
    $$Times Square at midnight. Felt obligated, regretted instantly.$$
  ]),
  ($$Just got back from Portugal — here is my itinerary$$, ARRAY[
    $$Skip Lisbon for the back half, end your trip in Porto. You will thank me.$$,
    $$Drive the N222. One of the best wine country roads on earth.$$,
    $$Algarve in May beats Algarve in August. Same beach, 30 percent the people.$$
  ]),
  ($$Six months of consistent lifting, finally seeing results$$, ARRAY[
    $$Year two is where the real ego death and actual gains happen. Keep going.$$,
    $$Compound lifts progressing is what matters. Squat, bench, dead, OHP, pull.$$,
    $$Sleep is the cheat. 6 to 8 hours doubled my recovery.$$
  ]),
  ($$Best home gym setup under $1000?$$, ARRAY[
    $$Used rack from Craigslist + barbell + 300lb plate set. Done.$$,
    $$Adjustable dumbbells (Bowflex 552 or PowerBlocks) cover 80 percent of workouts.$$,
    $$Bench, bar, plates, pull-up bar. Build slowly. Hoarding gear is its own trap.$$
  ]),
  ($$Cardio I actually enjoy$$, ARRAY[
    $$Trail running. Music in, phone off. Zero ego, all therapy.$$,
    $$Boxing class twice a week. Forgot it was cardio because I was having fun.$$,
    $$Cycling commute. 8 miles each way. Fitness as a side effect of life logistics.$$
  ]),
  ($$How do you stay motivated past day 90?$$, ARRAY[
    $$Track strength, not weight. Numbers go up, motivation follows.$$,
    $$Train with one specific person. Showing up for them is half the battle.$$,
    $$Pick a goal that requires consistency. Race, meet, hike. Without it you drift.$$
  ]),
  ($$Creatine — overrated or essential?$$, ARRAY[
    $$Most studied supplement on earth. Cheap, safe, works. Just take it.$$,
    $$Not essential, but cost benefit is absurd. 5g a day, end of story.$$,
    $$Do not expect miracles. Plateau breaker, not a magic pill.$$
  ]),
  ($$Just ran my first half marathon$$, ARRAY[
    $$Recovery week is non-negotiable. Easy miles only, ego stays home.$$,
    $$Mental jump from half to full is shorter than you think. Lock another in 6 months.$$,
    $$Get fitted shoes. Right pair is worth more than 6 weeks of training.$$
  ]),
  ($$Bodyweight-only workouts that actually work$$, ARRAY[
    $$Convict Conditioning + the Recommended Routine. That is the curriculum.$$,
    $$Rings transform bodyweight training. Cheap to buy, expensive to master.$$,
    $$Pistol squats, pullups, dips, handstand pushups. You will look great and bend in new ways.$$
  ]),
  ($$Calorie counting changed my life$$, ARRAY[
    $$First two weeks are eye opening. After three months it is background math.$$,
    $$Maintenance phase is the underrated win. Most skip it and rebound.$$,
    $$MacroFactor app. Worth every penny. Adjusts the deficit dynamically.$$
  ]),
  ($$Best stretch for desk workers?$$, ARRAY[
    $$Couch stretch. Two minutes a side. Will undo years of sitting.$$,
    $$Cat-cow and thoracic openers every morning. Five minutes, game changer for shoulders.$$,
    $$Hip flexor stretch with a glute bridge after. The opposing muscle has to do the work.$$
  ]),
  ($$Cutting vs maintaining — which is harder?$$, ARRAY[
    $$Cutting is mechanically easier, mentally harder. Maintaining is the opposite.$$,
    $$Most people never learn to maintain. They yo-yo between cut and bulk for life.$$,
    $$Maintaining requires monitoring without obsession. Hard to thread that needle.$$
  ])
)
INSERT INTO comments (post_id, author_id, body)
SELECT
  p.id,
  (SELECT u.id FROM users u
    WHERE u.username ~ '^(bria|char|dani|emil|fran|gabr|hele|isab|jose|kira)[0-9]+$'
      AND u.id <> p.author_id
    ORDER BY random() LIMIT 1),
  c.body
FROM per_post pp
JOIN posts p ON p.title = pp.title
CROSS JOIN LATERAL unnest(pp.comments) AS c(body)
WHERE NOT EXISTS (
  SELECT 1 FROM comments cm
  JOIN posts p2 ON p2.id = cm.post_id
  JOIN communities c2 ON c2.id = p2.community_id
  WHERE c2.name = 'askreddit'
);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DELETE FROM comments WHERE post_id IN (
  SELECT id FROM posts WHERE community_id IN (
    SELECT id FROM communities WHERE name IN
      ('askreddit','programming','gaming','news','science','movies','books','food','travel','fitness')
  )
);
DELETE FROM posts WHERE community_id IN (
  SELECT id FROM communities WHERE name IN
    ('askreddit','programming','gaming','news','science','movies','books','food','travel','fitness')
);
DELETE FROM memberships WHERE community_id IN (
  SELECT id FROM communities WHERE name IN
    ('askreddit','programming','gaming','news','science','movies','books','food','travel','fitness')
);
DELETE FROM communities WHERE name IN
  ('askreddit','programming','gaming','news','science','movies','books','food','travel','fitness');
DELETE FROM users WHERE username ~ '^(bria|char|dani|emil|fran|gabr|hele|isab|jose|kira)[0-9]+$';
-- +goose StatementEnd
