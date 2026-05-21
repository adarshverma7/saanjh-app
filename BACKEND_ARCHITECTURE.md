# Saanjh — Complete Backend Architecture & Implementation Plan
**Solo Developer Edition | May 2026 | Target: 1,000 → 1,00,000 users**

---

## SECTION 1: OVERALL BACKEND ARCHITECTURE

### Recommended Stack

**NestJS (Node.js + TypeScript) + PostgreSQL + Cloudflare R2 + Supabase**

This is the single best stack for a solo developer building Saanjh. Here is why each piece was chosen.

---

### Why NestJS over alternatives

**NestJS wins for Saanjh because:**
- Opinionated structure — you make fewer architecture decisions (modules, controllers, services, guards are defined patterns)
- TypeScript end-to-end — fewer runtime bugs, autocomplete everywhere
- Built-in: validation (class-validator), auth guards, WebSockets/SSE, Bull queue integration, caching, config management
- Scales from monolith to microservices without rewriting (extract modules later)
- Excellent ecosystem — every library you need has a NestJS wrapper

**Python/FastAPI:** Excellent framework but weaker ecosystem for real-time, queue management, and WebSockets compared to NestJS. Better for ML-heavy backends — not relevant for MVP.

**Firebase/Supabase as full backend:** Firebase Firestore is document-based, making relational queries (all entries for pair X in month Y, streak calculations, Memory Tree aggregations) expensive and awkward. Costs spike unpredictably. Hard to migrate away from. Supabase is excellent as a managed PostgreSQL host and auth layer — use it for that, not as your entire backend logic layer.

**Express:** Too unopinionated for a solo developer. You'll spend time building what NestJS gives you for free (middleware chains, validation, DI container).

---

### Why PostgreSQL over MongoDB

Saanjh's data is fundamentally relational:
- A diary connection is user_a ↔ user_b — a join
- Entries belong to a connection — a foreign key
- Memory Tree requires monthly aggregation — a GROUP BY query with window functions
- Streaks require date arithmetic — PostgreSQL handles this natively
- On This Day requires date-part extraction — `EXTRACT(MONTH FROM recorded_at)`

MongoDB would require you to denormalize everything, making streak/Memory Tree/On This Day queries into application-level code that's slow and error-prone.

PostgreSQL is ACID compliant. A voice memory that disappears because of a partial write failure would destroy user trust. ACID prevents this.

---

### Architecture Overview

```
Flutter App (Android + iOS)
         |
    HTTPS / SSE
         |
  ┌──────────────────┐
  │  NestJS API      │  ← Railway.app (single server for MVP)
  │  (Monolith)      │
  │                  │
  │  Modules:        │
  │  - AuthModule    │
  │  - DiaryModule   │
  │  - FlickerModule │
  │  - MediaModule   │
  │  - NotifModule   │
  │  - BookModule    │
  └──────┬───────────┘
         |
    ┌────┴────────────────────────────┐
    │                                 │
PostgreSQL                    Cloudflare R2
(Supabase managed)            (voice/video storage)
    │
  Redis ← (add at 2,000 users)
    │
Bull Queue ← (add at 500 users for transcription)
    │
Background Workers:
- TranscriptionWorker (Whisper API)
- NotificationWorker (FCM)
- PDFWorker (Memory Book)
```

---

### When to Introduce Each Technology

| Technology | When | Why |
|-----------|------|-----|
| NestJS + PostgreSQL | Day 1 | Core stack |
| Cloudflare R2 | Day 1 | Media storage (no egress fees) |
| Firebase Auth / MSG91 | Day 1 | OTP auth |
| FCM (via OneSignal) | Day 1 | Push notifications |
| Bull Queue | Month 1 | Async transcription jobs |
| Redis | 2,000 users | Session caching, rate limiting, SSE pub/sub |
| SSE (Server-Sent Events) | Month 3 | Real-time Flicker delivery |
| Read replica | 10,000 users | Read performance |
| Horizontal scaling | 20,000 users | Multiple API instances |
| Kubernetes | 1,00,000 users | Container orchestration |

---

## SECTION 2: INFRASTRUCTURE & DEPLOYMENT PLANNING

### Hosting Comparison for Indian Startup

| Service | Use case | MVP Cost | Pros | Cons |
|---------|---------|---------|------|------|
| Railway | NestJS API | $5/mo | Zero DevOps, GitHub auto-deploy, env vars UI | Less control |
| Render | NestJS API | Free-$7 | Free tier available | Spins down on free tier |
| Fly.io | NestJS API | $3-10/mo | Global edge, good latency India | CLI-heavy, more complex |
| DigitalOcean Droplet | API + DB | $12/mo | Full control, predictable | Manual DevOps |
| Supabase | PostgreSQL only | Free-$25 | Managed PG + backups + dashboard | Vendor dependency |
| Firebase | Full backend | Free→spike | Fastest to prototype | Lock-in, costly at scale |

**MVP Recommendation:**
- API server: **Railway** ($5/mo starter) — push to GitHub → auto-deploys → zero config SSL
- Database: **Supabase free tier** — managed PostgreSQL, daily backups, dashboard, 500MB storage
- Media: **Cloudflare R2** — 10GB free, zero egress fees, global CDN included
- Push notifications: **OneSignal** — free for up to 10,000 push subscribers
- Error tracking: **Sentry** — free 5,000 errors/month
- Uptime monitoring: **Uptime Robot** — free, alerts to phone

**Total MVP infra cost: ~$5-15/month**

---

### Environments

```
Local Dev → Staging → Production

Local:
  - NestJS runs on localhost:3000
  - Local PostgreSQL (Docker) or Supabase dev project
  - .env.local with dev secrets

Staging:
  - Railway preview environment (auto-created on PR)
  - Supabase staging project (separate database)
  - Test OTP provider (MSG91 test mode)
  - Real R2 bucket with staging prefix

Production:
  - Railway production environment
  - Supabase production project
  - Real SMS, real payments, real data
```

---

### CI/CD for Solo Developer

GitHub Actions — 20 lines, set and forget:

```yaml
# .github/workflows/deploy.yml
name: Deploy
on:
  push:
    branches: [main]
jobs:
  test-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - run: npm run test
      - run: npm run build
      # Railway auto-deploys on push to main — no extra step needed
```

Railway connects to your GitHub repo and deploys automatically on every push to `main`. Tests run first; if they fail, deploy is blocked.

---

### Backups Strategy

Voice memories are irreplaceable emotional data. Never lose them.

**PostgreSQL (Supabase):**
- Supabase free tier: 7-day point-in-time recovery
- Supabase Pro ($25/mo): 30-day PITR
- Additionally: weekly `pg_dump` to a separate R2 bucket via GitHub Actions cron

**Media (Cloudflare R2):**
- Enable versioning on the R2 bucket (keeps deleted objects for 90 days)
- Soft delete in DB — never hard-delete media immediately
- Monthly: sync production bucket to a cold-storage bucket (R2 lifecycle rules)

**Backup verification:**
- Monthly: restore test — restore latest DB dump to a temporary database, verify row counts

---

### Monitoring Stack (Affordable)

| Tool | Purpose | Cost |
|------|---------|------|
| Sentry | Backend errors + Flutter crashes | Free |
| Uptime Robot | API uptime, alert on down | Free |
| Railway Metrics | CPU, memory, request count | Included |
| Supabase Dashboard | DB query performance, slow queries | Included |
| Logtail | Log aggregation (search logs) | Free 1GB/day |

---

### Scaling Milestones

| Users | Action |
|-------|--------|
| 0-1,000 | Single Railway server, Supabase free |
| 1,000-2,000 | Upgrade Supabase to Pro ($25/mo), add Redis |
| 2,000-10,000 | Upgrade Railway plan, add read replica |
| 10,000-50,000 | Move to DigitalOcean managed Kubernetes |
| 50,000+ | Horizontal scaling, CDN optimization, self-hosted Whisper |

---

## SECTION 3: DATABASE SCHEMA DESIGN

All tables use UUID primary keys, `created_at`/`updated_at` timestamps, and soft delete where applicable. PostgreSQL on Supabase.

---

### users

```sql
CREATE TABLE users (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone             VARCHAR(15) UNIQUE NOT NULL,        -- E.164: +91XXXXXXXXXX
  phone_hash        VARCHAR(64) NOT NULL,               -- SHA-256 for contact matching
  name              VARCHAR(100),
  avatar_key        TEXT,                               -- R2 object key (not URL)
  language          VARCHAR(10) DEFAULT 'en',           -- 'en', 'hi'
  timezone          VARCHAR(50) DEFAULT 'Asia/Kolkata',
  date_of_birth     DATE,
  is_onboarded      BOOLEAN DEFAULT false,
  is_verified       BOOLEAN DEFAULT false,
  is_active         BOOLEAN DEFAULT true,
  last_active_at    TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  deleted_at        TIMESTAMPTZ                         -- soft delete
);

CREATE INDEX idx_users_phone_hash   ON users(phone_hash);
CREATE INDEX idx_users_last_active  ON users(last_active_at) WHERE deleted_at IS NULL;
```

Normalization note: `avatar_key` stores the R2 object key, not a full URL. URLs are signed at query time. This lets you change CDN domains without a migration.

---

### diary_connections

```sql
CREATE TABLE diary_connections (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_a_id             UUID NOT NULL REFERENCES users(id),
  user_b_id             UUID NOT NULL REFERENCES users(id),
  -- INVARIANT: user_a_id < user_b_id always (enforced by CHECK + app logic)
  -- This makes the pair unique without ordering ambiguity
  relationship_type     VARCHAR(30),  -- 'parent_child','partners','siblings','friends'
  initiated_by          UUID REFERENCES users(id),
  status                VARCHAR(20) DEFAULT 'pending',
                        -- 'pending','active','paused','ended'
  name_for_a            VARCHAR(100), -- how user_a named this diary
  name_for_b            VARCHAR(100), -- how user_b named this diary
  streak_count          INTEGER DEFAULT 0,
  longest_streak        INTEGER DEFAULT 0,
  streak_last_date      DATE,
  streak_started_at     DATE,
  diary_weather         VARCHAR(20) DEFAULT 'sunny',
                        -- 'sunny','partly_cloudy','cloudy','dormant'
  last_entry_at         TIMESTAMPTZ,
  total_entry_count     INTEGER DEFAULT 0,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_a_id, user_b_id),
  CHECK(user_a_id < user_b_id)
);

CREATE INDEX idx_conn_a      ON diary_connections(user_a_id) WHERE status = 'active';
CREATE INDEX idx_conn_b      ON diary_connections(user_b_id) WHERE status = 'active';
CREATE INDEX idx_conn_weather ON diary_connections(diary_weather, last_entry_at);
```

Query helper (use in all connection lookups):
```sql
-- Find connection for any user pair, regardless of ordering
SELECT * FROM diary_connections
WHERE (user_a_id = $1 AND user_b_id = $2)
   OR (user_a_id = $2 AND user_b_id = $1);
```

---

### diary_entries

```sql
CREATE TABLE diary_entries (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  connection_id         UUID NOT NULL REFERENCES diary_connections(id) ON DELETE CASCADE,
  author_id             UUID NOT NULL REFERENCES users(id),
  entry_type            VARCHAR(10) NOT NULL,   -- 'voice', 'video'
  media_key             TEXT NOT NULL,          -- R2 object key
  duration_seconds      SMALLINT,               -- max 20
  file_size_bytes       INTEGER,
  thumbnail_key         TEXT,                   -- R2 key, video only
  transcription         TEXT,
  transcription_status  VARCHAR(20) DEFAULT 'pending',
                        -- 'pending','processing','done','failed','skipped'
  mood                  VARCHAR(20),
                        -- 'happy','calm','thoughtful','missing','excited'
  is_starred            BOOLEAN DEFAULT false,
  starred_at            TIMESTAMPTZ,
  play_count            SMALLINT DEFAULT 0,
  recorded_at           TIMESTAMPTZ DEFAULT now(),
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now(),
  deleted_at            TIMESTAMPTZ             -- soft delete ONLY
);

-- Primary thread query: all entries for a connection, newest first
CREATE INDEX idx_entries_thread
  ON diary_entries(connection_id, recorded_at DESC)
  WHERE deleted_at IS NULL;

-- Author lookup (for personal stats)
CREATE INDEX idx_entries_author
  ON diary_entries(author_id, recorded_at DESC)
  WHERE deleted_at IS NULL;

-- Starred entries (Memory Jar)
CREATE INDEX idx_entries_starred
  ON diary_entries(connection_id, starred_at DESC)
  WHERE is_starred = true AND deleted_at IS NULL;

-- On This Day: match on month + day regardless of year
CREATE INDEX idx_entries_anniversary
  ON diary_entries(
    connection_id,
    EXTRACT(MONTH FROM recorded_at)::INT,
    EXTRACT(DAY FROM recorded_at)::INT
  )
  WHERE deleted_at IS NULL;

-- Memory Tree: monthly aggregation
CREATE INDEX idx_entries_monthly
  ON diary_entries(connection_id, DATE_TRUNC('month', recorded_at))
  WHERE deleted_at IS NULL;

-- Transcription search (full-text)
CREATE INDEX idx_entries_fts
  ON diary_entries USING GIN(to_tsvector('english', COALESCE(transcription, '')))
  WHERE deleted_at IS NULL;
```

Never hard-delete a diary entry. `deleted_at` is the maximum you do. Media is retained in R2 for 90 days after soft delete before a cleanup job removes it — giving users a grace period.

---

### flicker_events

```sql
CREATE TABLE flicker_events (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  connection_id         UUID NOT NULL REFERENCES diary_connections(id),
  sender_id             UUID NOT NULL REFERENCES users(id),
  receiver_id           UUID NOT NULL REFERENCES users(id),
  sent_at               TIMESTAMPTZ DEFAULT now(),
  delivered_at          TIMESTAMPTZ,            -- when FCM confirmed delivery
  is_mutual             BOOLEAN DEFAULT false,
  mutual_at             TIMESTAMPTZ,
  mutual_window_secs    INTEGER DEFAULT 300     -- 5-minute mutual reveal window
);

CREATE INDEX idx_flicker_connection  ON flicker_events(connection_id, sent_at DESC);
CREATE INDEX idx_flicker_receiver    ON flicker_events(receiver_id, sent_at DESC);
-- Used for mutual reveal check
CREATE INDEX idx_flicker_window
  ON flicker_events(sender_id, receiver_id, sent_at DESC);
```

Mutual reveal logic (run on every Flicker send):
```sql
-- After User A sends Flicker, check if User B sent one within the window
SELECT id FROM flicker_events
WHERE sender_id = $receiver_id      -- B sent
  AND receiver_id = $sender_id      -- to A
  AND sent_at >= now() - ($window_secs || ' seconds')::INTERVAL
  AND is_mutual = false
LIMIT 1;
-- If found: mark both flickers is_mutual=true, mutual_at=now()
```

---

### personal_journal_entries

```sql
-- Completely isolated from diary_connections. No partner ever touches this.
CREATE TABLE personal_journal_entries (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  entry_type        VARCHAR(10),   -- 'voice', 'video', 'text'
  media_key         TEXT,          -- NULL for text entries
  text_content      TEXT,          -- NULL for voice/video
  duration_seconds  SMALLINT,
  mood              VARCHAR(20),
  is_starred        BOOLEAN DEFAULT false,
  recorded_at       TIMESTAMPTZ DEFAULT now(),
  created_at        TIMESTAMPTZ DEFAULT now(),
  deleted_at        TIMESTAMPTZ
);

CREATE INDEX idx_personal_user
  ON personal_journal_entries(user_id, recorded_at DESC)
  WHERE deleted_at IS NULL;
```

Row-level security note: If using Supabase RLS, add policy: `USING (user_id = auth.uid())`. This makes it impossible at the database layer for any other user to read journal entries.

---

### streak_milestones

```sql
CREATE TABLE streak_milestones (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  connection_id   UUID NOT NULL REFERENCES diary_connections(id),
  milestone_days  INTEGER NOT NULL,   -- 7, 30, 100, 365
  achieved_at     TIMESTAMPTZ DEFAULT now(),
  seen_by_a       BOOLEAN DEFAULT false,
  seen_by_b       BOOLEAN DEFAULT false,
  UNIQUE(connection_id, milestone_days)
);
```

Milestone trigger: run after every new diary entry in the streak update function. Check if new `streak_count` equals a milestone value not yet in this table — insert it and queue a push notification.

Milestone values: `[7, 30, 60, 100, 200, 365]`

---

### notifications

```sql
CREATE TABLE notifications (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type          VARCHAR(50) NOT NULL,
  -- 'new_entry','flicker_received','streak_reminder','milestone',
  -- 'occasion','memory_jar','morning_ritual','system'
  title         TEXT,
  body          TEXT,
  data          JSONB,        -- { connection_id, entry_id, occasion_id, etc. }
  is_read       BOOLEAN DEFAULT false,
  read_at       TIMESTAMPTZ,
  push_status   VARCHAR(20) DEFAULT 'pending',
  -- 'pending','sent','delivered','failed','skipped'
  push_error    TEXT,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_notif_user_unread
  ON notifications(user_id, created_at DESC)
  WHERE is_read = false;
```

---

### notification_preferences

```sql
CREATE TABLE notification_preferences (
  user_id              UUID PRIMARY KEY REFERENCES users(id),
  new_entry            BOOLEAN DEFAULT true,
  flicker_received       BOOLEAN DEFAULT true,
  streak_reminder      BOOLEAN DEFAULT true,
  streak_reminder_time TIME DEFAULT '20:00:00',
  occasion_reminders   BOOLEAN DEFAULT true,
  morning_ritual       BOOLEAN DEFAULT true,
  morning_ritual_time  TIME DEFAULT '08:00:00',
  quiet_hours_start    TIME DEFAULT '22:00:00',
  quiet_hours_end      TIME DEFAULT '07:00:00',
  updated_at           TIMESTAMPTZ DEFAULT now()
);
```

---

### occasions

```sql
CREATE TABLE occasions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  connection_id       UUID NOT NULL REFERENCES diary_connections(id),
  created_by          UUID NOT NULL REFERENCES users(id),
  occasion_type       VARCHAR(30),
  -- 'birthday','anniversary','diwali','eid','holi','raksha_bandhan','custom'
  occasion_name       VARCHAR(100),
  occasion_date       DATE NOT NULL,
  is_recurring        BOOLEAN DEFAULT true,
  remind_days_before  INTEGER DEFAULT 3,
  last_reminded_year  INTEGER,
  created_at          TIMESTAMPTZ DEFAULT now()
);

-- Cron job queries this index daily to find upcoming occasions
CREATE INDEX idx_occasions_upcoming
  ON occasions(
    EXTRACT(MONTH FROM occasion_date)::INT,
    EXTRACT(DAY FROM occasion_date)::INT
  );
```

---

### occasion_ai_messages

```sql
CREATE TABLE occasion_ai_messages (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  connection_id   UUID REFERENCES diary_connections(id),
  occasion_id     UUID REFERENCES occasions(id),
  occasion_type   VARCHAR(30),
  prompt_used     TEXT,
  generated_text  TEXT,
  language        VARCHAR(10) DEFAULT 'en',
  model_used      VARCHAR(50),
  used_at         TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT now()
);
```

---

### memory_book_orders

```sql
CREATE TABLE memory_book_orders (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  connection_id         UUID NOT NULL REFERENCES diary_connections(id),
  ordered_by            UUID NOT NULL REFERENCES users(id),
  order_type            VARCHAR(10) DEFAULT 'self',  -- 'self', 'gift'
  gift_recipient_name   VARCHAR(100),
  gift_recipient_phone  VARCHAR(15),
  date_from             DATE NOT NULL,
  date_to               DATE NOT NULL,
  entry_count           INTEGER,
  amount_paise          INTEGER NOT NULL,     -- ₹399 = 39900 paise
  currency              VARCHAR(3) DEFAULT 'INR',
  razorpay_order_id     VARCHAR(100),
  razorpay_payment_id   VARCHAR(100),
  payment_status        VARCHAR(20) DEFAULT 'pending',
  -- 'pending','paid','failed','refunded'
  paid_at               TIMESTAMPTZ,
  pdf_key               TEXT,                -- R2 key for generated PDF
  print_status          VARCHAR(20) DEFAULT 'not_started',
  -- 'not_started','generating_pdf','pdf_ready','sent_to_printer','shipped','delivered'
  shipping_address      JSONB,
  tracking_number       VARCHAR(100),
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);
```

---

### invites

```sql
CREATE TABLE invites (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inviter_id          UUID NOT NULL REFERENCES users(id),
  invite_code         VARCHAR(12) UNIQUE NOT NULL,
  invited_phone       VARCHAR(15),       -- stored for UX ("Waiting for Maa...")
  invited_phone_hash  VARCHAR(64),       -- for matching on signup
  relationship_type   VARCHAR(30),
  connection_name     VARCHAR(100),      -- what inviter named this connection
  status              VARCHAR(20) DEFAULT 'pending',
  -- 'pending','accepted','expired','cancelled'
  accepted_by         UUID REFERENCES users(id),
  accepted_at         TIMESTAMPTZ,
  click_count         INTEGER DEFAULT 0,
  expires_at          TIMESTAMPTZ DEFAULT (now() + INTERVAL '7 days'),
  created_at          TIMESTAMPTZ DEFAULT now()
);

CREATE UNIQUE INDEX idx_invites_code        ON invites(invite_code);
CREATE INDEX idx_invites_phone_hash
  ON invites(invited_phone_hash) WHERE status = 'pending';
CREATE INDEX idx_invites_inviter
  ON invites(inviter_id, created_at DESC);
```

---

### device_sessions

```sql
CREATE TABLE device_sessions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id     VARCHAR(100) NOT NULL,
  device_type   VARCHAR(10),              -- 'android', 'ios'
  fcm_token     TEXT,
  app_version   VARCHAR(20),
  os_version    VARCHAR(20),
  is_active     BOOLEAN DEFAULT true,
  last_used_at  TIMESTAMPTZ DEFAULT now(),
  created_at    TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, device_id)
);

CREATE INDEX idx_sessions_user_active
  ON device_sessions(user_id) WHERE is_active = true;
```

---

### otp_verifications

```sql
CREATE TABLE otp_verifications (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone         VARCHAR(15) NOT NULL,
  otp_hash      VARCHAR(64) NOT NULL,     -- SHA-256 of OTP, never plain text
  purpose       VARCHAR(20) DEFAULT 'login',  -- 'login', 'delete_account'
  attempt_count SMALLINT DEFAULT 0,
  is_used       BOOLEAN DEFAULT false,
  expires_at    TIMESTAMPTZ DEFAULT (now() + INTERVAL '10 minutes'),
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_otp_phone ON otp_verifications(phone, created_at DESC);
```

---

### memory_tree_cache

```sql
-- Denormalized: recomputed asynchronously, not on every request
CREATE TABLE memory_tree_cache (
  connection_id     UUID PRIMARY KEY REFERENCES diary_connections(id),
  monthly_data      JSONB NOT NULL DEFAULT '[]',
  -- [{year_month:'2026-05', entry_count:5, voice:3, video:2,
  --   mood_dist:{happy:2,calm:3}, health:0.8}]
  total_entries     INTEGER DEFAULT 0,
  active_months     INTEGER DEFAULT 0,
  tree_health       NUMERIC(3,2) DEFAULT 0.0,  -- 0.0 to 1.0
  last_computed_at  TIMESTAMPTZ DEFAULT now()
);
```

Invalidate this cache whenever a diary entry is created or deleted for that connection. Recompute asynchronously via Bull queue.

---

### feature_flags

```sql
CREATE TABLE feature_flags (
  key                 VARCHAR(100) PRIMARY KEY,
  is_enabled          BOOLEAN DEFAULT false,
  rollout_percentage  INTEGER DEFAULT 0,   -- 0-100, for gradual rollout
  description         TEXT,
  updated_at          TIMESTAMPTZ DEFAULT now()
);

-- Seed data
INSERT INTO feature_flags VALUES
  ('video_entries', false, 0, 'Video diary entries'),
  ('occasion_ai', false, 0, 'AI occasion message generation'),
  ('memory_book', false, 0, 'Physical Memory Book ordering'),
  ('transcription', true, 100, 'Voice transcription via Whisper');
```

---

### audit_logs

```sql
CREATE TABLE audit_logs (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID REFERENCES users(id),
  action        VARCHAR(100) NOT NULL,
  -- 'entry.created','entry.deleted','account.deleted','connection.ended'
  resource_type VARCHAR(50),
  resource_id   UUID,
  metadata      JSONB,     -- additional context, NEVER transcription content
  ip_address    INET,
  created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_audit_user   ON audit_logs(user_id, created_at DESC);
CREATE INDEX idx_audit_action ON audit_logs(action, created_at DESC);
-- Partition this table by month after 100,000 rows
```

---

### rate_limit_counters

```sql
-- Simple DB-based rate limiting for MVP (replace with Redis later)
CREATE TABLE rate_limit_counters (
  key           VARCHAR(200) PRIMARY KEY,
  -- 'otp:+91XXXXXXXXXX', 'flicker:user_id:connection_id'
  count         INTEGER DEFAULT 1,
  window_start  TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now()
);
```

---

## SECTION 4: COMPLETE API PLAN

**Base URL:** `https://api.saanjh.app/v1`
**Auth:** All protected endpoints require `Authorization: Bearer <access_token>`
**Error format:**
```json
{
  "error": {
    "code": "INVALID_OTP",
    "message": "OTP is incorrect or expired",
    "details": null
  }
}
```

---

### AUTH APIS

```
POST /v1/auth/otp/send
  Auth: None
  Rate limit: 3 per phone per 10 min | 15 per IP per hour
  Body:   { "phone": "+91XXXXXXXXXX" }
  Returns: { "message": "OTP sent", "expires_in": 600 }
  Errors:
    400 INVALID_PHONE     — not a valid Indian mobile number
    429 RATE_LIMIT        — too many OTP requests

POST /v1/auth/otp/verify
  Auth: None
  Rate limit: 5 attempts per OTP session, then lockout
  Body:   { "phone": "+91XXXXXXXXXX", "otp": "123456" }
  Returns: {
    "access_token": "...",      // 15-min JWT
    "refresh_token": "...",     // 30-day rotating token
    "is_new_user": true,
    "user": { "id", "name", "is_onboarded" }
  }
  Errors:
    400 INVALID_OTP       — wrong OTP
    400 OTP_EXPIRED       — 10 minutes passed
    429 TOO_MANY_ATTEMPTS — 5 wrong attempts

POST /v1/auth/token/refresh
  Auth: None (uses refresh token in body)
  Body:   { "refresh_token": "..." }
  Returns: { "access_token": "...", "refresh_token": "..." }
  Note: Old refresh token is immediately invalidated (rotation)
  Errors:
    401 INVALID_TOKEN
    401 TOKEN_EXPIRED

POST /v1/auth/logout
  Auth: Required
  Body:   { "device_id": "..." }
  Returns: { "message": "Logged out" }
  Action: Marks device_session inactive, invalidates refresh token

GET /v1/auth/sessions
  Auth: Required
  Returns: list of active device sessions for current user
  Use: "Manage devices" screen

DELETE /v1/auth/sessions/:session_id
  Auth: Required
  Use: Remote logout of a specific device

POST /v1/auth/account/delete/request
  Auth: Required
  Action: Sends OTP to phone for deletion confirmation
  Returns: { "message": "OTP sent for account deletion" }

POST /v1/auth/account/delete/confirm
  Auth: Required
  Body:   { "otp": "123456" }
  Action: Soft-deletes user, queues hard-delete job for 30 days
  Returns: { "message": "Account deletion scheduled in 30 days" }
```

---

### ONBOARDING APIS

```
GET /v1/onboarding/status
  Auth: Required
  Returns: {
    "step": "profile" | "connection" | "complete",
    "profile_complete": false,
    "has_connection": false
  }

PUT /v1/onboarding/profile
  Auth: Required
  Body: {
    "name": "Adarsh",
    "language": "hi",
    "date_of_birth": "1998-03-15",  // optional
    "timezone": "Asia/Kolkata"
  }
  Validates: name required, language in ['en','hi']
  Returns: { "user": UserProfile }

POST /v1/onboarding/avatar/upload-url
  Auth: Required
  Returns: { "upload_url": "...", "avatar_key": "..." }
  Use: Pre-signed R2 URL for avatar upload

PATCH /v1/onboarding/avatar
  Auth: Required
  Body:   { "avatar_key": "..." }
  Returns: { "user": UserProfile }

POST /v1/onboarding/complete
  Auth: Required
  Action: Sets is_onboarded = true
  Returns: { "message": "Welcome to Saanjh" }
```

---

### DIARY CONNECTION APIS

```
POST /v1/connections/invite
  Auth: Required
  Rate limit: 10 per user per day | max 3 pending at a time
  Body: {
    "phone": "+91XXXXXXXXXX",       // optional: specific person
    "relationship_type": "parent_child",
    "connection_name": "Maa"
  }
  Returns: {
    "invite_id": "uuid",
    "invite_code": "SAANJ42",
    "deep_link": "https://saanjh.app/join/SAANJ42",
    "whatsapp_message": "Maa, I'm using Saanjh...",
    "expires_at": "2026-05-27T00:00:00Z"
  }
  Errors:
    409 ALREADY_CONNECTED — active connection with this phone exists
    429 INVITE_LIMIT      — too many pending invites

GET /v1/connections/invite/:code
  Auth: None (used by invited user before signup)
  Returns: {
    "valid": true,
    "inviter_name": "Adarsh",
    "relationship_type": "parent_child",
    "expires_at": "..."
  }
  Errors:
    404 INVITE_NOT_FOUND
    410 INVITE_EXPIRED

POST /v1/connections/invite/:code/accept
  Auth: Required (invited user, post-signup)
  Body: { "connection_name": "Beta" }
  Action: Creates diary_connection, marks invite accepted
  Returns: { "connection": DiaryConnection }
  Errors:
    409 ALREADY_CONNECTED

GET /v1/connections
  Auth: Required
  Returns: {
    "connections": [{
      "id": "uuid",
      "partner": { "id", "name", "avatar_url", "last_active_at" },
      "relationship_type": "parent_child",
      "connection_name": "Maa",
      "status": "active",
      "streak_count": 14,
      "diary_weather": "sunny",
      "last_entry_at": "...",
      "unread_count": 2       // entries partner posted, not yet played
    }]
  }

GET /v1/connections/:id
  Auth: Required (must be member of connection)
  Returns: { "connection": DiaryConnectionDetail }

PATCH /v1/connections/:id/name
  Auth: Required
  Body: { "name": "Maa ki awaaz" }
  Returns: { "connection": DiaryConnection }

GET /v1/connections/:id/health
  Auth: Required
  Cache: 5 minutes per connection
  Returns: {
    "streak_count": 14,
    "diary_weather": "sunny",
    "total_entries": 87,
    "entries_this_week": 5,
    "last_entry_at": "...",
    "days_since_last_entry": 0
  }
```

---

### DIARY ENTRY APIS

```
POST /v1/connections/:id/entries/upload-url
  Auth: Required (must be member of connection)
  Rate limit: 30 per connection per day
  Body: {
    "entry_type": "voice",          // "voice" | "video"
    "file_extension": "m4a",        // "m4a" | "mp4"
    "duration_seconds": 18,
    "file_size_bytes": 245000
  }
  Validates:
    - duration_seconds <= 20
    - file_size_bytes <= 10_000_000 (10MB)
    - entry_type in ['voice','video']
  Returns: {
    "upload_url": "https://r2.cloudflarestorage.com/...", // 15-min expiry
    "media_key": "voice/conn_id/2026/05/entry_id.m4a",
    "expires_in": 900
  }

POST /v1/connections/:id/entries
  Auth: Required
  Body: {
    "media_key": "voice/conn_id/2026/05/entry_id.m4a",
    "entry_type": "voice",
    "duration_seconds": 18,
    "mood": "happy",                // optional
    "recorded_at": "2026-05-20T..."  // optional, defaults to now()
  }
  Action:
    1. Verify media_key exists in R2 (HEAD request to confirm upload succeeded)
    2. Insert diary_entry row
    3. Update connection.last_entry_at, total_entry_count
    4. Update streak (complex logic — see Section 10)
    5. Invalidate memory_tree_cache for this connection
    6. Queue: transcription job (if voice)
    7. Queue: push notification to partner
    8. Push SSE event to partner (if online)
  Returns: { "entry": DiaryEntry }
  Errors:
    400 MEDIA_NOT_FOUND   — R2 object doesn't exist yet
    400 INVALID_ENTRY_TYPE

GET /v1/connections/:id/entries
  Auth: Required
  Query params:
    limit: 20 (max 50)
    cursor: base64-encoded { recorded_at, id } for cursor pagination
    filter: "all" | "voice" | "video" | "starred"
  Cache: 60 seconds, invalidated on new entry
  Returns: {
    "entries": [DiaryEntry],
    "next_cursor": "base64..." | null,
    "total_count": 87             // from connection.total_entry_count
  }

GET /v1/connections/:id/entries/:entry_id
  Auth: Required
  Action: Generates a signed R2 URL (1-hour expiry) for media playback
  Returns: {
    "entry": DiaryEntry,
    "media_url": "https://r2.../signed...",   // 1-hour signed URL
    "thumbnail_url": "..."                     // if video
  }

PATCH /v1/connections/:id/entries/:entry_id/star
  Auth: Required
  Body: { "is_starred": true }
  Returns: { "entry": DiaryEntry }

DELETE /v1/connections/:id/entries/:entry_id
  Auth: Required (ONLY the author can delete)
  Action: Sets deleted_at = now() (soft delete only)
  Returns: { "message": "Entry removed" }
  Note: Media file in R2 retained for 90 days before cleanup job runs

PATCH /v1/connections/:id/entries/:entry_id/played
  Auth: Required
  Action: Increments play_count, updates unread tracking
  Returns: { "play_count": 3 }
```

---

### Flicker APIS

```
POST /v1/connections/:id/flicker
  Auth: Required
  Rate limit: 10 per connection per hour
  Body: {} (empty)
  Action:
    1. Insert flicker_event row
    2. Check mutual reveal window (SQL query)
    3. If mutual: update both flickers, push SSE + notification
    4. If not mutual: push notification to partner (FCM)
  Returns: {
    "flicker_id": "uuid",
    "is_mutual": false,
    "mutual_at": null,
    "window_closes_at": "2026-05-20T14:35:00Z"
  }

GET /v1/connections/:id/flicker/latest
  Auth: Required
  Cache: 30 seconds
  Returns: {
    "my_last_Flicker_at": "...",
    "partner_last_Flicker_at": "...",
    "is_mutual": false,
    "window_closes_at": "..."   // null if no active window
  }

GET /v1/connections/:id/flicker/history
  Auth: Required
  Query: limit: 30, cursor: string
  Returns: { "Flickers": [FlickerEvent], "next_cursor": "..." }
```

---

### MEMORY TREE APIS

```
GET /v1/connections/:id/memory-tree
  Auth: Required
  Cache: 10 minutes (from memory_tree_cache table)
  Returns: {
    "months": [{
      "year_month": "2026-05",
      "entry_count": 8,
      "voice_count": 6,
      "video_count": 2,
      "mood_distribution": { "happy": 3, "calm": 3, "missing": 2 },
      "has_milestone": false,
      "node_health": 0.9         // 0.0-1.0, drives tree node visual
    }],
    "tree_health": 0.85,         // overall
    "diary_weather": "sunny",
    "streak_count": 14,
    "longest_streak": 30,
    "total_entries": 87,
    "active_months": 6
  }

GET /v1/connections/:id/memory-tree/:year_month
  Auth: Required
  Path: year_month format "2026-05"
  Query: filter: "all"|"voice"|"video"|"starred"
  Returns: {
    "entries": [DiaryEntry],     // entries for that month
    "month_stats": {
      "entry_count": 8,
      "mood_distribution": {...},
      "node_health": 0.9
    }
  }
```

---

### ON THIS DAY APIS

```
GET /v1/connections/:id/on-this-day
  Auth: Required
  Query: date: "YYYY-MM-DD" (defaults to today in user's timezone)
  Cache: 1 hour (same day entries don't change)
  Returns: {
    "entries": [DiaryEntry],    // entries from same month+day in past years
    "years": [2024, 2025],      // years that have entries
    "has_entries": true
  }
  Note: Query uses idx_entries_anniversary index on (month, day) extraction
```

---

### MEMORY JAR APIS

```
GET /v1/connections/:id/memory-jar/surface
  Auth: Required
  Use: Called on home screen open, time-gated (once per 4 hours per connection)
  Returns: {
    "entry": DiaryEntry | null,
    "total_starred": 12,
    "surfaced": true            // false if within gate window
  }

GET /v1/connections/:id/memory-jar
  Auth: Required
  Query: limit: 20, cursor: string
  Returns: { "entries": [DiaryEntry], "next_cursor": "..." }
```

---

### STREAK & MILESTONE APIS

```
GET /v1/connections/:id/streak
  Auth: Required
  Cache: 5 minutes
  Returns: {
    "current_streak": 14,
    "longest_streak": 30,
    "streak_started_at": "2026-05-06",
    "days_since_last_entry": 0,
    "at_risk": false,          // true if no entry yet today
    "total_entry_days": 45,
    "milestones": [{
      "days": 7,
      "achieved_at": "2026-05-12",
      "seen_by_me": true
    }]
  }

POST /v1/connections/:id/milestones/:days/seen
  Auth: Required
  Action: Marks milestone as seen by current user (so celebration doesn't re-show)
  Returns: { "ok": true }
```

---

### OCCASION APIS

```
GET /v1/connections/:id/occasions
  Auth: Required
  Returns: { "occasions": [Occasion] }

POST /v1/connections/:id/occasions
  Auth: Required
  Body: {
    "occasion_type": "birthday",
    "occasion_name": "Maa's Birthday",
    "occasion_date": "1965-11-14",
    "is_recurring": true,
    "remind_days_before": 3
  }
  Returns: { "occasion": Occasion }

DELETE /v1/connections/:id/occasions/:occasion_id
  Auth: Required
  Returns: { "message": "Occasion removed" }

POST /v1/connections/:id/occasions/:occasion_id/generate-message
  Auth: Required
  Rate limit: 5 per occasion per day
  Body: { "language": "hi", "tone": "warm" }
  Action: Calls Claude API with occasion context, saves result
  Returns: { "message": "Beta, aaj tumhari janam...", "id": "uuid" }
```

---

### PERSONAL JOURNAL APIS

```
POST /v1/journal/upload-url
  Auth: Required
  Body: { "entry_type": "voice", "file_extension": "m4a", "duration_seconds": 45 }
  Note: No 20-second limit for personal journal
  Returns: { "upload_url": "...", "media_key": "..." }

POST /v1/journal/entries
  Auth: Required
  Body: { "entry_type", "media_key"?, "text_content"?, "duration_seconds"?, "mood"? }
  Returns: { "entry": PersonalJournalEntry }

GET /v1/journal/entries
  Auth: Required
  Query: limit: 20, cursor: string, filter: "all"|"voice"|"text"|"starred"
  Returns: { "entries": [PersonalJournalEntry], "next_cursor": "..." }

GET /v1/journal/entries/:id
  Auth: Required
  Returns: { "entry": PersonalJournalEntry, "media_url": "..." }

PATCH /v1/journal/entries/:id/star
  Auth: Required
  Body: { "is_starred": boolean }
  Returns: { "entry": PersonalJournalEntry }

DELETE /v1/journal/entries/:id
  Auth: Required
  Action: Soft delete
  Returns: { "message": "Entry removed" }
```

---

### NOTIFICATION APIS

```
GET /v1/notifications
  Auth: Required
  Query: limit: 30, unread_only: boolean, cursor: string
  Returns: {
    "notifications": [Notification],
    "unread_count": 5,
    "next_cursor": "..."
  }

POST /v1/notifications/read
  Auth: Required
  Body: { "notification_ids": ["uuid1","uuid2"] | "all" }
  Returns: { "updated_count": 2 }

GET /v1/notifications/preferences
  Auth: Required
  Returns: { "preferences": NotificationPreferences }

PUT /v1/notifications/preferences
  Auth: Required
  Body: Partial<NotificationPreferences>
  Returns: { "preferences": NotificationPreferences }

POST /v1/notifications/device-token
  Auth: Required
  Body: {
    "fcm_token": "...",
    "device_id": "...",
    "device_type": "android",
    "app_version": "1.0.0"
  }
  Action: Upsert device_session row
  Returns: { "message": "Token registered" }
```

---

### MEMORY BOOK APIS

```
POST /v1/memory-books/preview
  Auth: Required
  Body: { "connection_id": "uuid", "date_from": "2025-01-01", "date_to": "2026-05-20" }
  Returns: {
    "entry_count": 87,
    "estimated_pages": 90,
    "price_paise": 39900,       // ₹399
    "sample_entries": [3 DiaryEntry]
  }

POST /v1/memory-books/orders
  Auth: Required
  Body: {
    "connection_id": "uuid",
    "order_type": "self",       // "self" | "gift"
    "date_from": "2025-01-01",
    "date_to": "2026-05-20",
    "shipping_address": {
      "name": "Adarsh Kumar",
      "line1": "123 MG Road",
      "city": "Bengaluru",
      "state": "Karnataka",
      "pincode": "560001",
      "phone": "+91XXXXXXXXXX"
    },
    "gift_recipient": null      // { name, phone } for gift orders
  }
  Action:
    1. Create memory_book_orders row (payment_status: pending)
    2. Create Razorpay order
    3. Return Razorpay order details for Flutter to open payment sheet
  Returns: {
    "order_id": "uuid",
    "razorpay_order_id": "order_XXXXXX",
    "amount_paise": 39900,
    "currency": "INR",
    "razorpay_key": "rzp_live_XXXXXX"   // public key safe to send
  }

POST /v1/memory-books/orders/:id/payment/verify
  Auth: Required
  Body: {
    "razorpay_payment_id": "pay_XXXXXX",
    "razorpay_order_id": "order_XXXXXX",
    "razorpay_signature": "..."
  }
  Action:
    1. Verify Razorpay signature (HMAC-SHA256)
    2. Update order payment_status = 'paid'
    3. Queue PDF generation job
    4. Send order confirmation notification
  Returns: { "order": MemoryBookOrder }

GET /v1/memory-books/orders
  Auth: Required
  Returns: { "orders": [MemoryBookOrder] }

GET /v1/memory-books/orders/:id
  Auth: Required
  Returns: { "order": MemoryBookOrder }
```

---

### INVITE APIS

```
GET /v1/invites
  Auth: Required
  Returns: { "invites": [Invite] }
  Use: Show "Waiting for Maa..." pending invite status

DELETE /v1/invites/:id
  Auth: Required
  Action: Cancel a pending invite
  Returns: { "message": "Invite cancelled" }
```

---

### SEARCH APIS

```
GET /v1/search/entries
  Auth: Required
  Query: q: string (min 3 chars), connection_id?: uuid, limit: 20
  Uses: PostgreSQL full-text search on transcription column
  Returns: {
    "entries": [DiaryEntry with highlighted snippet],
    "total_matches": 12
  }
  Note: Only available after transcription. Voice entries without
        transcription are not searchable.
```

---

### SETTINGS APIS

```
GET /v1/settings
  Auth: Required
  Returns: { "settings": { language, timezone, ... } }

PATCH /v1/settings
  Auth: Required
  Body: Partial<UserSettings>
  Returns: { "settings": UserSettings }

GET /v1/settings/feature-flags
  Auth: Required
  Action: Returns enabled flags for this user (respects rollout_percentage)
  Returns: { "flags": { "video_entries": false, "transcription": true } }

GET /v1/settings/data-export
  Auth: Required
  Action: Queues data export job (DPDP Act compliance)
  Returns: { "message": "Export will be ready in ~10 minutes. You'll get a notification." }
```

---

### ADMIN APIS (Internal — separate JWT secret, IP-whitelist)

```
GET    /v1/admin/users                    — list with filters
GET    /v1/admin/users/:id                — user detail + connection list
PATCH  /v1/admin/users/:id/suspend        — suspend account
GET    /v1/admin/analytics/overview       — DAU, WAU, new signups, retention
GET    /v1/admin/analytics/entries        — entry counts per day
GET    /v1/admin/analytics/Flickers         — flicker counts per day
GET    /v1/admin/feature-flags            — list all flags
PATCH  /v1/admin/feature-flags/:key       — toggle flag / set rollout %
GET    /v1/admin/orders                   — memory book orders with status
PATCH  /v1/admin/orders/:id               — update print_status, tracking_number
GET    /v1/admin/invites/stats            — invite conversion rates
```

---

## SECTION 5: INVITE & CONTACT SYSTEM

### WhatsApp-Based Invite Flow (Step by Step)

```
Step 1  Adult child opens Saanjh, taps "Invite Maa"
Step 2  App calls POST /v1/connections/invite
        { phone: "+91XXXXXXXXXX", relationship_type: "parent_child", connection_name: "Maa" }
Step 3  Backend:
        a. Generates invite_code: "SAANJ42" (8 alphanumeric chars)
        b. Stores invited_phone_hash = SHA256(normalize(phone) + SERVER_SALT)
        c. Generates deep link: https://saanjh.app/join/SAANJ42
        d. Builds WhatsApp message:
           "Maa, main Saanjh use kar raha hoon — ek app jisme main tumhe
            rozana voice notes bhej sakta hoon. Join karo yahan se:
            https://saanjh.app/join/SAANJ42"
Step 4  App opens WhatsApp via:
        whatsapp://send?phone=91XXXXXXXXXX&text=URL-encoded-message
        (If WhatsApp not installed: opens native share sheet)
Step 5  Maa receives WhatsApp message, clicks deep link
Step 6  Deep link handling:
        Android: App Links (verified domain) opens app if installed
        iOS: Universal Links opens app if installed
        If not installed: redirects to Play Store / App Store
        After install + OTP signup: Flutter reads invite_code from
        initial link using app_links or flutter_branch_io package
Step 7  Signup flow detects pending invite:
        a. Compute phone_hash of Maa's number
        b. Query: SELECT * FROM invites WHERE invited_phone_hash = $1 AND status = 'pending'
        c. If found: auto-call POST /v1/connections/invite/:code/accept
        d. Connection created, both users see shared diary immediately
Step 8  Adarsh's app receives push + SSE: "Maa has joined Saanjh!"
```

### Invite Code Generation

```typescript
generateInviteCode(): string {
  // No 0, O, 1, I — too ambiguous if user types manually
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return Array.from(crypto.randomBytes(8))
    .map(b => chars[b % chars.length])
    .join('');
}
```

### Phone Number Hashing

```typescript
const PHONE_HASH_SALT = process.env.PHONE_HASH_SALT; // 32-char secret, never rotated

function hashPhone(rawPhone: string): string {
  const normalized = normalizeToE164(rawPhone); // → +91XXXXXXXXXX
  return crypto.createHmac('sha256', PHONE_HASH_SALT).update(normalized).digest('hex');
}
```

Why HMAC-SHA256 not bcrypt: bcrypt is intentionally slow (good for passwords, bad for
bulk contact matching). HMAC-SHA256 is fast — you can hash 10,000 contacts in under 1s.
The server salt prevents rainbow table attacks on the stored hashes.

### "Contacts on Saanjh" Detection (Phase 2)

```
Flutter requests contact permission
→ Reads device contacts (phone numbers only, not names)
→ POST /v1/contacts/check { "phone_hashes": ["hash1", "hash2", ...] }  // max 500
→ Backend: SELECT phone_hash FROM users WHERE phone_hash = ANY($1)
→ Returns: { "found_hashes": ["hash1"] }
→ Flutter cross-references: which contact name maps to found_hash
→ Shows "Connect" for existing users, "Invite" for non-users

Privacy guarantee: server never learns which contacts the user has —
only whether specific hashes exist in the database.
```

### Abuse Prevention for Invites

```
Rate limits:
  - 10 invites sent per user per day
  - 3 pending (unaccepted) invites max
  - 1 invite per phone number per 24 hours (prevent harassment)
  - Block invites from accounts created < 24 hours ago

Flagging:
  - invite_code clicked >20 times → flag for review (suspicious sharing)
  - User sends invites to >50 different numbers in a week → auto-suspend

Expiry:
  - Invites expire after 7 days
  - Daily cron job cleans up expired invites
```

---

## SECTION 6: NOTIFICATIONS ARCHITECTURE

### Notification Types

| Type | Trigger | Channel | Priority |
|------|---------|---------|----------|
| new_entry | Partner posts voice/video | Push + In-app | High |
| flicker_received | Partner sends Flicker | Push + In-app | High |
| streak_reminder | No entry by 8 PM today | Push only | Medium |
| milestone | Streak hits 7/30/100/365 | Push + In-app | High |
| occasion | 3 days before saved occasion | Push + In-app | High |
| memory_jar | App open (4-hour gate) | In-app only | Low |
| morning_ritual | First open of the day | In-app only | Low |

### Delivery Architecture

```
API Event (new entry created)
    ↓
NotificationService.queue(userId, type, data)
    ↓
Bull Queue: 'notifications'
    ↓
NotificationWorker:
  1. Fetch user's notification_preferences
  2. Check quiet hours (user timezone)
  3. Check preference toggle for this type
  4. If push allowed: fetch FCM tokens → send via OneSignal
  5. Record push_status in notifications table
  6. Insert notification row (always — for in-app bell)
```

### Scheduled Notifications (NestJS Cron)

```typescript
// Streak reminder — daily at 18:00 IST
// Sends to users who have no entry today by ~20:00 their local time
@Cron('0 18 * * *', { timeZone: 'Asia/Kolkata' })
async sendStreakReminders() {
  const atRisk = await this.db.query(`
    SELECT dc.id, dc.user_a_id, dc.user_b_id
    FROM diary_connections dc
    WHERE dc.status = 'active'
      AND dc.streak_count > 0
      AND dc.streak_last_date < CURRENT_DATE
      AND NOT EXISTS (
        SELECT 1 FROM diary_entries de
        WHERE de.connection_id = dc.id
          AND DATE(de.recorded_at AT TIME ZONE 'Asia/Kolkata') = CURRENT_DATE
          AND de.deleted_at IS NULL
      )
  `);
  for (const conn of atRisk.rows) {
    await this.notifQueue.add('push', { userId: conn.user_a_id, type: 'streak_reminder', data: conn });
    await this.notifQueue.add('push', { userId: conn.user_b_id, type: 'streak_reminder', data: conn });
  }
}

// Occasion reminders — daily at 07:00 IST
@Cron('0 7 * * *', { timeZone: 'Asia/Kolkata' })
async sendOccasionReminders() {
  const upcoming = await this.db.query(`
    SELECT o.*, dc.user_a_id, dc.user_b_id
    FROM occasions o
    JOIN diary_connections dc ON o.connection_id = dc.id
    WHERE EXTRACT(MONTH FROM o.occasion_date + (o.remind_days_before || ' days')::INTERVAL)
          = EXTRACT(MONTH FROM CURRENT_DATE)
      AND EXTRACT(DAY FROM o.occasion_date + (o.remind_days_before || ' days')::INTERVAL)
          = EXTRACT(DAY FROM CURRENT_DATE)
      AND (o.last_reminded_year IS NULL OR o.last_reminded_year < EXTRACT(YEAR FROM CURRENT_DATE))
  `);
  // Queue reminders for both users in each connection
}
```

### FCM vs OneSignal

OneSignal (MVP): Free 10k subscribers, single API for Android+iOS, easy dashboard.
Direct FCM (Scale): Free, unlimited, no vendor dependency, but separate APNs setup for iOS.
Recommendation: OneSignal for MVP. Migrate to direct FCM at 10,000+ users.

### Notification Templates

```typescript
const TEMPLATES = {
  new_entry: {
    title: '{{partner_name}} left you a voice note',
    body: '{{duration}}s — tap to listen',
  },
  flicker_received: {
    title: '{{partner_name}} is thinking of you',
    body: 'They sent you a Flicker',
  },
  streak_reminder: {
    title: 'Your streak is at risk',
    body: "{{streak_count}} days with {{partner_name}} — don't break it",
  },
  milestone: {
    title: '{{streak_count}} days together',
    body: 'You and {{partner_name}} hit a milestone',
  },
  occasion: {
    title: '{{occasion_name}} is in {{days_away}} days',
    body: 'Record something special for {{partner_name}}',
  },
};
```

### Retry Strategy

```
Attempt 1 → immediately
Attempt 2 → 5 minutes later (Bull delayed job)
Attempt 3 → 30 minutes later
All fail → mark push_status='failed', still visible in in-app bell

FCM 410 (token invalid) → immediately deactivate device_session, no retry
```

---

## SECTION 7: REAL-TIME ARCHITECTURE

### SSE vs WebSockets Decision

Saanjh's real-time needs are one-directional (server → client):
- "Partner sent Flicker" — server pushes to client
- "New entry" — server pushes to client
- "Mutual reveal" — server pushes to client

WebSockets are bidirectional. There is no bidirectional real-time use case in Saanjh at MVP.
SSE is simpler, automatic reconnection built-in, works through all proxies, and NestJS supports it natively.
Use SSE for MVP. Add WebSockets only if you build a text chat feature.

### NestJS SSE Implementation

```typescript
@Controller('connections')
export class ConnectionEventsController {
  @Sse(':id/events')
  @UseGuards(JwtAuthGuard, ConnectionMemberGuard)
  liveEvents(
    @Param('id') connectionId: string,
    @CurrentUser() user: User,
  ): Observable<MessageEvent> {
    return this.eventsService.getStream(user.id, connectionId);
  }
}

@Injectable()
export class EventsService {
  private subjects = new Map<string, Subject<MessageEvent>>();

  getStream(userId: string, connectionId: string): Observable<MessageEvent> {
    const key = `${userId}:${connectionId}`;
    if (!this.subjects.has(key)) this.subjects.set(key, new Subject());
    const heartbeat$ = interval(25000).pipe(
      map(() => ({ data: { type: 'heartbeat' } } as MessageEvent))
    );
    return merge(this.subjects.get(key)!.asObservable(), heartbeat$);
  }

  push(userId: string, connectionId: string, event: object) {
    const key = `${userId}:${connectionId}`;
    this.subjects.get(key)?.next({ data: event } as MessageEvent);
  }
}
```

Flutter listens via the `eventsource` or `http` SSE packages and processes events:
```dart
// types: flicker_received, mutual_reveal, new_entry, heartbeat
```

### Flicker Mutual Reveal Flow

```
T+0:00  User A sends Flicker
        → INSERT flicker_event (sender=A, receiver=B)
        → Check: has B sent to A in last 300s? NO
        → Push FCM to B: "A is thinking of you"
        → Push SSE to A: { type:'flicker_sent', window_closes_at: T+5:00 }

T+2:30  User B sends Flicker back (opened app from notification)
        → INSERT flicker_event (sender=B, receiver=A)
        → Check: has A sent to B in last 300s? YES (at T+0:00)
        → UPDATE both flickers: is_mutual=true, mutual_at=now()
        → Push SSE to B: { type:'mutual_reveal', mutual_at }
        → Push SSE to A: { type:'mutual_reveal', mutual_at }
        → Push FCM to A if offline: "You and B shared a Flicker moment"
```

### Online/Offline Presence

No true real-time presence at MVP. Update `last_active_at` on every authenticated request via middleware:

```typescript
@Injectable()
export class ActivityMiddleware implements NestMiddleware {
  async use(req: Request, res: Response, next: NextFunction) {
    if (req.user?.id) {
      // Fire-and-forget — does not block the request
      this.usersService.touchLastActive(req.user.id).catch(() => {});
    }
    next();
  }
}
```

Flutter shows: "Active now" (<5 min), "Active 2h ago", "Active today", "Active X days ago"

### Redis Pub/Sub (Add at 2,000+ Users)

When Railway auto-scales to 2+ API instances, SSE connections are split across servers.
Server 1 cannot push to a client on Server 2. Fix: Redis pub/sub as event bus.

```
Server 1 handles API: "User A sent Flicker"
  → Redis PUBLISH saanjh:user:{USER_B_ID} { event_data }

Server 2 has User B's SSE connection
  → Subscribed to: SUBSCRIBE saanjh:user:{USER_B_ID}
  → Receives event → pushes down SSE stream
```

For MVP (single server): the in-memory Subject map is sufficient.

---

## SECTION 8: MEDIA HANDLING

### Upload Pipeline

```
Flutter                        API Server                  Cloudflare R2
  |                                |                             |
  |-- POST /entries/upload-url --->|                             |
  |   { type, ext, duration }      |-- Generate signed URL ----->|
  |                                |<- signed PUT URL -----------|
  |<- { upload_url, media_key } ---|                             |
  |                                |                             |
  |-- PUT upload_url (binary) ------------------------------------------>|
  |   (direct to R2, NOT through API server)               |-- Stores file
  |<- 200 OK ------------------------------------------------------|
  |                                |                             |
  |-- POST /entries -------------->|                             |
  |   { media_key, duration, mood }|-- HEAD media_key ---------->|
  |                                |   (verify upload succeeded) |
  |                                |<- 200 OK -------------------|
  |                                |-- INSERT diary_entries       |
  |                                |-- Queue transcription job    |
  |                                |-- Push SSE/FCM to partner    |
  |<- { entry: DiaryEntry } -------|                             |
```

### Media Key Structure

```
entries/shared/{connection_id}/{YYYY}/{MM}/{entry_id}.m4a   — voice
entries/shared/{connection_id}/{YYYY}/{MM}/{entry_id}.mp4   — video
entries/thumbs/{connection_id}/{YYYY}/{MM}/{entry_id}.jpg   — video thumbnail
entries/journal/{user_id}/{YYYY}/{MM}/{entry_id}.m4a        — personal journal
avatars/{user_id}/{timestamp}.jpg
books/{order_id}/memory_book.pdf
```

Year/month in key path enables R2 lifecycle rules per time period.

### Transcription Services Comparison

| Service | Cost/min | Hindi | Notes |
|---------|---------|-------|-------|
| OpenAI Whisper API | $0.006 | Excellent | Simplest integration |
| Deepgram Nova-2 | $0.0043 | Good | Faster latency |
| Google STT | $0.004 | Excellent | More complex setup |
| AssemblyAI | $0.0065 | Good | Nice dashboard |

20s clip cost: OpenAI = $0.002 = ₹0.17 per clip
At 500 clips/day: ₹85/day → ₹2,550/month. Acceptable for MVP.
Recommendation: OpenAI Whisper for MVP. Switch to Deepgram at scale.

```typescript
@Process('transcribe_voice')
async handleTranscription(job: Job<{ entryId: string; mediaKey: string; connectionId: string }>) {
  const { entryId, mediaKey, connectionId } = job.data;
  const audioBuffer = await this.r2.getObject(mediaKey);
  const transcription = await this.openai.audio.transcriptions.create({
    file: new File([audioBuffer], 'audio.m4a', { type: 'audio/m4a' }),
    model: 'whisper-1',
    language: 'hi',
    response_format: 'text',
  });
  await this.db.query(
    `UPDATE diary_entries SET transcription=$1, transcription_status='done' WHERE id=$2`,
    [transcription, entryId]
  );
  await this.eventsService.broadcastToConnection(connectionId, {
    type: 'transcription_ready', entry_id: entryId,
  });
}
```

### Storage Comparison

| Service | Storage/GB | Egress/GB | Free tier | India CDN |
|---------|-----------|----------|-----------|-----------|
| Cloudflare R2 | $0.015 | FREE | 10GB + 1M ops | Yes |
| AWS S3 | $0.023 | $0.085 | 5GB (12mo) | Via CloudFront |
| Backblaze B2 | $0.006 | $0.01 | 10GB | Via Cloudflare |
| Supabase Storage | Free 1GB | Limited | 1GB | No |

At 1,000 users × 10 plays/day × 100KB = 1GB egress/day = 30GB/month.
S3 egress cost: 30 × $0.085 = $2.55/month. R2 egress: $0.
Use Cloudflare R2 from day one.

### Signed URLs

```typescript
async getSignedPlayUrl(mediaKey: string, expiresIn = 3600): Promise<string> {
  const command = new GetObjectCommand({
    Bucket: process.env.R2_BUCKET_NAME,
    Key: mediaKey,
  });
  return getSignedUrl(this.s3Client, command, { expiresIn });
}
```

Never return public R2 URLs. All media URLs in API responses are signed, 1-hour expiry.
Flutter re-fetches when a 403 error occurs on playback.

### Memory Book PDF Generation

```typescript
@Process('generate_memory_book_pdf')
async handlePdfGeneration(job: Job<{ orderId: string }>) {
  const order = await this.ordersRepo.findOne(job.data.orderId);
  const entries = await this.entriesRepo.findForRange(
    order.connection_id, order.date_from, order.date_to
  );
  const doc = new PDFDocument({ size: 'A5', margin: 40 });
  for (const entry of entries) {
    doc.addPage();
    doc.fontSize(9).text(format(entry.recorded_at, 'dd MMMM yyyy'), { align: 'right' });
    doc.moveDown();
    if (entry.transcription) {
      doc.fontSize(13).text(`"${entry.transcription}"`, { align: 'center' });
    }
    doc.fontSize(8).fillColor('#888')
       .text(`${entry.duration_seconds}s voice note`, { align: 'center' });
  }
  const pdfKey = `books/${order.id}/memory_book.pdf`;
  await this.r2.putObject(pdfKey, await streamToBuffer(doc), 'application/pdf');
  await this.ordersRepo.update(order.id, { pdf_key: pdfKey, print_status: 'pdf_ready' });
}
```

MVP print fulfillment: admin receives notification → downloads PDF → sends to local print shop.
Phase 2: integrate Printbindery or Canvera API for automated printing + shipping.

---

## SECTION 9: SECURITY & EMOTIONAL DATA TRUST

### Indian SMS OTP Providers

| Provider | Cost/SMS | DLT Required | Notes |
|---------|---------|-------------|-------|
| MSG91 | ₹0.16 | Yes | Best for India, good API |
| 2Factor | ₹0.15 | Yes | Cheapest, decent uptime |
| Twilio | ₹1.40 | Yes | Expensive for India |
| Firebase Auth | Free (10k/mo) | No | Easy MVP, less control |

DLT Registration: TRAI mandates this for all transactional SMS since 2021.
Register on Jio Trueconnect or Vodafone DLT. Takes 3-7 working days.
Template example: "Your Saanjh OTP is {#var#}. Valid 10 minutes. -SAANJH"

Recommendation: Firebase Auth for MVP (no DLT, no backend OTP code).
Migrate to MSG91 at Phase 2 (cheaper, more control, DLT registered).

### JWT Strategy

```
Access token:  15-minute expiry, RS256 signed, payload: { sub, session_id, device_id }
Refresh token: 30-day expiry, opaque 64-byte hex, stored as SHA-256 hash in DB
Rotation:      New refresh token on every use. Old token invalidated immediately.

Storage in Flutter:
  Access token:  in-memory (Dart variable) — short enough not to need secure storage
  Refresh token: flutter_secure_storage (Android Keystore / iOS Keychain)
```

### Connection Ownership Guard (Core Privacy Boundary)

```typescript
@Injectable()
export class ConnectionMemberGuard implements CanActivate {
  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest();
    const { id: connectionId } = req.params;
    const userId = req.user.id;

    const result = await this.db.query(
      `SELECT 1 FROM diary_connections
       WHERE id = $1 AND status = 'active'
         AND (user_a_id = $2 OR user_b_id = $2)`,
      [connectionId, userId]
    );

    if (!result.rows.length) throw new ForbiddenException();
    return true;
  }
}
```

This guard is applied to every diary, flicker, memory tree, and occasion endpoint.
It is the only thing standing between a user and another person's emotional data.
It must never be skipped.

### Admin Access Policy

Admins can view: user metadata (name, phone, joined date, account status).
Admins cannot view: diary entry content, transcription text, personal journal, flicker history.
Admin API returns entry counts and timestamps only — never content.
This is enforced in code, not just policy.

### Encryption

```
In transit:  HTTPS/TLS 1.3 (Railway + Cloudflare enforce — no extra work)
At rest:     Supabase PostgreSQL: AES-256 (Google Cloud managed)
             Cloudflare R2: AES-256 (automatic)
OTPs:        Stored as SHA-256 hash only — never plain text
Refresh tokens: Stored as SHA-256 hash only
Phone numbers: Stored plain (needed for SMS delivery) + separately hashed for matching
Transcriptions: Never logged, never in admin responses, never in error messages
```

### GDPR + Indian DPDP Act Compliance

```
User rights implementation:

1. Right to access (data export):
   GET /v1/settings/data-export
   → Queues job → produces ZIP: entry metadata, transcriptions, flicker history
   → Excludes raw audio (too large — user can download from app directly)
   → Ready within 72 hours → notification sent
   → ZIP available via signed URL for 7 days

2. Right to erasure (account delete):
   POST /v1/auth/account/delete/request  (send OTP)
   POST /v1/auth/account/delete/confirm  (verify OTP)
   → Soft delete user row (deleted_at = now())
   → 30-day grace period (can cancel by logging back in)
   → Day 30 hard delete job:
     - Hard delete: users, device_sessions, notification_preferences, otp_verifications
     - Soft-deleted entries: author metadata anonymized ("Deleted User")
     - Partner's copy of shared entries: RETAINED (partner is also a data subject)
     - Queue R2 media deletion for personal journal only
     - Shared diary media: retained until partner also deletes

3. Consent:
   - Explicit checkbox before OTP (not pre-checked)
   - Privacy policy and Terms linked before signup
   - No implied consent — user must actively check box

4. Data retention:
   - Active accounts: retained indefinitely (user's choice)
   - OTP records: deleted 24 hours after use
   - Audit logs: 2 years, then purge
   - Soft-deleted entries: media cleaned from R2 after 90 days
```

### Secrets Management

```
All secrets live in Railway's environment variables UI.
Never in .env files committed to git.
.env.example in repo — keys only, no values.

Required secrets:
  DATABASE_URL           Supabase PostgreSQL connection string
  JWT_PRIVATE_KEY        RS256 private key (PEM format)
  JWT_PUBLIC_KEY         RS256 public key (PEM format)
  REFRESH_TOKEN_SECRET   64-char random hex
  PHONE_HASH_SALT        32-char random hex (NEVER rotate — breaks existing hashes)
  R2_ACCESS_KEY_ID       Cloudflare R2
  R2_SECRET_ACCESS_KEY   Cloudflare R2
  R2_BUCKET_NAME         Cloudflare R2
  R2_ENDPOINT            https://{account_id}.r2.cloudflarestorage.com
  OPENAI_API_KEY         Whisper transcription
  ONESIGNAL_APP_ID       Push notifications
  ONESIGNAL_API_KEY      Push notifications
  RAZORPAY_KEY_ID        Payment (public key — also sent to Flutter)
  RAZORPAY_KEY_SECRET    Payment (server only)
  MSG91_AUTH_KEY         SMS OTP (Phase 2)
  ADMIN_JWT_SECRET       Separate secret for admin-only routes
  REDIS_URL              (Phase 2)
```

---

## SECTION 10: MVP ROADMAP

### Phase 1 — Ship MVP (Months 0–3)
Target: 1,000 users, voice diary works end-to-end.

Build in this exact order:

**Week 1–2: Foundation**
- NestJS project with TypeScript, ESLint, Prettier
- PostgreSQL schema migrations: users, diary_connections, diary_entries, device_sessions, otp_verifications
- Firebase Auth OTP integration
- JWT access + refresh token middleware
- ConnectionMemberGuard
- GET /v1/health
- Railway + Supabase + R2 environments wired up

**Week 3–4: Core Diary**
- POST /connections/invite (WhatsApp link generation)
- GET /connections/invite/:code
- POST /connections/invite/:code/accept
- GET /connections (with unread_count)
- POST /entries/upload-url + POST /entries (voice only)
- GET /entries (cursor-paginated thread)
- GET /entries/:id (with signed R2 URL)
- PATCH /entries/:id/star
- DELETE /entries/:id (soft delete)

**Week 5–6: Engagement**
- Flicker send + receive (FCM push, no SSE yet)
- Streak update logic (get this right — see Appendix)
- On This Day API
- Memory Jar (starred entry surface)
- FCM via OneSignal: new entry, flicker, streak milestone
- notification_preferences (save + read)
- POST /notifications/device-token

**Week 7–8: Launch Prep**
- Transcription via OpenAI Whisper (Bull queue)
- Streak milestone detection + push
- Personal Journal APIs
- Rate limiting (DB-based simple counters)
- Sentry error tracking
- Uptime Robot monitoring
- GitHub Actions CI/CD
- Staging environment fully operational
- End-to-end test: OTP → onboarding → invite → voice entry → partner notification → play

**Skip for Phase 1 (explicitly):**
- Video entries — voice-only is the core emotional experience
- Memory Book — placeholder "Coming Soon" button in Flutter
- Occasion AI messages — static suggestion strings in Flutter
- Memory Tree filter — show all months only
- SSE real-time — 30-second polling is fine for 1,000 users
- Redis — PostgreSQL fast enough
- Admin dashboard — use Supabase dashboard directly
- Search API — barely any transcriptions yet
- Data export — legal but zero users need it on day 1

**What NOT to over-engineer in Phase 1:**
- Rate limiting: simple DB counter rows, no Redis
- Transcription: call Whisper synchronously with 10s timeout if no Bull queue yet
- Memory Tree: compute fresh on each request (no cache table)
- Notifications: OneSignal handles delivery and retry
- Error responses: Sentry catches it — no elaborate error taxonomy needed

**Worth investing in from Day 1:**
- Auth security: OTP hashing, JWT rotation, connection ownership guard — non-negotiable
- Soft delete: never hard-delete emotional content — ever
- Database schema: get relationships and indexes right upfront — migrations later are painful
- Media key naming: organized R2 structure enables lifecycle policies at scale
- Audit logging: basic (user_id, action, timestamp) — invaluable when debugging user reports

---

### Phase 2 — Growth (Months 3–9)
Target: 5,000 users, retention loops working.

- Video diary entries (same upload pipeline, Flutter compresses)
- Firebase Dynamic Links for WhatsApp deep-link invites
- Memory Book orders: Razorpay + PDF generation
- Occasion system: save occasions, cron reminders, Claude API AI messages
- Memory Tree cache table (async Bull recomputation)
- Memory Tree filter chips working end-to-end (fixes audit finding)
- SSE for real-time Flicker delivery
- Redis for session caching + rate limiting
- Basic admin dashboard (read-only React, analytics only)
- Mixpanel: track signup, first entry, 7-day retention, Memory Book conversion
- Full-text search on transcriptions
- Personal Journal navigation entry point (fixes audit finding)
- Streak milestone celebration screen wiring (fixes audit finding)
- Morning ritual trigger endpoint

---

### Phase 3 — Scale (Months 9–24)
Target: 1,00,000 users.

Infrastructure:
- 2–3 Railway API instances + Redis pub/sub for SSE distribution
- PostgreSQL read replica for analytics queries
- audit_logs partitioned by month
- diary_entries partitioned by year

Features:
- AI memory surfacing: "You recorded this 1 year ago — want to reshare?"
- Memory Book gift flow (gift to partner, second delivery address)
- Contact-based discovery ("3 of your contacts use Saanjh")
- Self-hosted Whisper on GPU (cost reduction)
- Hindi/Devanagari full UI
- Referral analytics dashboard
- Diaspora timezone handling (NRI users outside IST)

---

## SECTION 11: COST OPTIMIZATION

### Monthly Infra Cost — 1,000 Active Users

| Service | Plan | USD/mo | INR/mo |
|---------|------|--------|--------|
| Railway (NestJS API) | Starter | $5 | ₹420 |
| Supabase (PostgreSQL) | Free | $0 | ₹0 |
| Cloudflare R2 | Free 10GB | $0 | ₹0 |
| OneSignal (push) | Free 10k | $0 | ₹0 |
| Firebase Auth (OTP) | Free 10k/mo | $0 | ₹0 |
| OpenAI Whisper | ~300 clips/day | ~$18 | ~₹1,500 |
| Sentry | Free | $0 | ₹0 |
| GitHub Actions | Free | $0 | ₹0 |
| **Total** | | **~$23/mo** | **~₹1,920/mo** |

Whisper is the dominant cost. To reduce:
- Skip transcription for Month 1 — launch without it, add in Month 2
- Transcribe on-demand only (when user taps to see transcript) instead of every clip

### Upgrade Milestones

| Users | Action | Additional Cost |
|-------|--------|----------------|
| 500 | Add Railway worker for Bull queue | +$5/mo |
| 1,000 | Upgrade Supabase to Pro (30-day backups) | +$25/mo |
| 2,000 | Add Redis on Railway | +$10/mo |
| 5,000 | Upgrade Railway plan | +$15/mo |
| 10,000 | Migrate OTP to MSG91 (saves vs Firebase overages) | saves ₹2k/mo |
| 50,000 | Move to DigitalOcean managed infra | ~$200/mo total |

### Razorpay vs Cashfree

| Feature | Razorpay | Cashfree |
|---------|---------|---------|
| Transaction fee | 2% + ₹3 | 1.75% |
| UPI / GPay | Yes | Yes |
| Settlement | T+3 | T+2 |
| Flutter SDK | Excellent | Good |
| Startup program | 0% for 6 months | Similar |
| Brand trust | Higher | Lower |

Use Razorpay. Apply for their startup program: 0% fee on first ₹5,00,000 transactions.
On ₹399 orders with standard 2%: ₹7.98 per order. Negligible.

### SMS OTP Cost Optimization

Phase 1 (Firebase Auth, free): handles 10,000 OTPs/month — covers MVP.
Phase 2 (MSG91, ₹0.16/SMS):
- 5,000 users × 2 logins/month = 10,000 SMS = ₹1,600/month

Optimization tricks:
- 10-minute OTP validity reduces re-send rate vs 5-minute
- Device trust: skip OTP for 30 days on same trusted device after first login
- Magic link via WhatsApp as fallback for failed SMS (Interakt: ₹0.40/msg but higher delivery)

### Free Tiers to Maximize

```
Supabase free tier:
  - 500MB DB storage → ~50,000 diary_entries rows (each ~500 bytes)
  - 1GB file storage → upgrade to R2 before this fills
  - 50,000 auth users → plenty for Phase 1

Cloudflare R2 free tier:
  - 10GB storage → ~100,000 voice clips at 100KB each
  - 1M write ops/month → plenty for 1,000 users × 1 upload/day
  - 10M read ops/month → plenty for playback

OneSignal free:
  - 10,000 push subscribers → covers 3,000–5,000 users (avg 2 devices)

Sentry free:
  - 5,000 errors/month → sufficient for MVP

GitHub Actions free:
  - 2,000 minutes/month → ~100 deploys of a 20-minute CI job
```

---

## SECTION 12: PRODUCTION READINESS CHECKLIST

### Backend Readiness
- [ ] App starts cleanly in NODE_ENV=production
- [ ] All environment variables documented in .env.example (keys only)
- [ ] No secrets in source code (run: git grep -i "secret\|api_key\|password")
- [ ] GET /v1/health returns { status:'ok', db:'ok', timestamp }
- [ ] Graceful shutdown: SIGTERM closes DB pool, drains Bull queue
- [ ] Global exception filter: unhandled errors return { error: { code, message } }
- [ ] Request body size limit set (adjust NestJS default 100KB → 1MB)
- [ ] CORS configured: production domain only, no wildcard
- [ ] Helmet.js security headers on all responses

### API Readiness
- [ ] All protected endpoints return 401 without valid JWT
- [ ] ConnectionMemberGuard on all diary, flicker, memory tree, occasion endpoints
- [ ] Consistent error format across all 40+ endpoints
- [ ] Input validation (class-validator DTOs) on all request bodies
- [ ] Cursor pagination on all list endpoints (no offset pagination)
- [ ] Rate limiting active on: OTP, upload-url, flicker, invite, occasion AI
- [ ] /v1/ version prefix on all routes

### Media Pipeline Readiness
- [ ] Pre-signed upload URLs expire in 15 minutes
- [ ] Server does HEAD check on media_key before creating diary_entries row
- [ ] All media access URLs in responses are signed (no public R2 URLs)
- [ ] File type whitelist: .m4a, .mp4, .jpg only
- [ ] Max file size checked before issuing upload URL (10MB video, 2MB voice)
- [ ] Transcription Bull job retries 3x with exponential backoff
- [ ] Daily cron: clean orphaned R2 objects (uploads started, entry never created)

### Database Readiness
- [ ] All migrations run on a fresh Supabase database without errors
- [ ] All indexes from schema created — verify with EXPLAIN ANALYZE on key queries:
      diary thread, On This Day, Memory Tree aggregation, starred entries
- [ ] DB connection pool max set (10 for Supabase free tier limit)
- [ ] Slow query log enabled (Supabase dashboard)
- [ ] deleted_at on all user-content tables (diary_entries, personal_journal_entries, users)
- [ ] No N+1 queries in: diary thread, connections list, memory tree
- [ ] Backup restore tested: restored latest dump to temp DB, verified row counts match

### Deployment Readiness
- [ ] GitHub Actions CI: test must pass before Railway deploys
- [ ] Staging mirrors production (separate Supabase project, separate R2 bucket)
- [ ] Zero-downtime deploys (Railway default)
- [ ] DB migrations run before app starts (in Procfile or Railway start command)
- [ ] One-click Railway rollback verified
- [ ] Full end-to-end smoke test on staging: OTP → invite → record → play → flicker

### Monitoring Readiness
- [ ] Sentry DSN in NestJS (backend) and Flutter (app)
- [ ] Uptime Robot: monitors GET /v1/health every 5 minutes, SMS alert on down
- [ ] Railway metrics dashboard bookmarked (CPU, memory, request latency)
- [ ] Supabase slow query alert: alert if any query > 500ms
- [ ] Log drain configured (Railway → Logtail or Papertrail)
- [ ] Alert rule: >10 Sentry errors/minute → email notification

### Security Readiness
- [ ] OTP brute force: 5 wrong attempts → 30-minute lockout for that phone
- [ ] Refresh token rotation: old token invalidated immediately on refresh
- [ ] JWT expiry: 15-minute access confirmed (decode a token and check exp)
- [ ] HTTPS enforced: test HTTP request → should 301 to HTTPS
- [ ] X-Content-Type-Options: nosniff header present
- [ ] X-Frame-Options: DENY header present
- [ ] Parameterized queries only — no string concatenation in SQL
- [ ] Privacy policy live at saanjh.app/privacy before first user
- [ ] Account deletion flow tested end-to-end (30-day grace confirmed)
- [ ] PHONE_HASH_SALT confirmed in Railway env vars, not in codebase

### Scalability Readiness
- [ ] API server is stateless (no local disk state, no in-memory sessions per user)
- [ ] All media stored in Cloudflare R2 (not on Railway server disk)
- [ ] DB connection pool configured (not unlimited connections)
- [ ] No synchronous blocking I/O in request handlers
- [ ] Heavy operations in background jobs: transcription, PDF, bulk notifications
- [ ] Load test: k6 or Artillery — diary thread endpoint at 100 concurrent users < 300ms P95
- [ ] Memory Tree query verified: EXPLAIN ANALYZE shows index scan (not seq scan)

---

## APPENDIX: QUICK REFERENCE

### Project Structure (NestJS)

```
src/
  auth/            OTP, JWT, guards, decorators
  users/           profile, settings, data export
  connections/     diary connections, invite CRUD
  entries/         diary entries, upload URLs, play tracking
  flicker/          flicker events, SSE event streaming
  memory-tree/     tree cache, monthly aggregation jobs
  journal/         personal journal (completely isolated)
  notifications/   push delivery, preferences, templates
  occasions/       CRUD, cron reminders, AI message generation
  memory-books/    orders, Razorpay, PDF generation
  search/          full-text entry search
  admin/           admin-only routes (separate guard + JWT secret)
  shared/
    database/      TypeORM / Drizzle setup + migrations
    storage/       Cloudflare R2 service
    config/        environment validation (Joi schema)
  workers/         Bull queue processors
    transcription.worker.ts
    notification.worker.ts
    pdf.worker.ts
    cleanup.worker.ts
```

### Key Architecture Decisions

| Decision | Choice | Reason |
|---------|--------|--------|
| API framework | NestJS (TypeScript) | Opinionated, built-in modules, solo-dev friendly |
| Database | PostgreSQL (Supabase) | Relational, ACID, managed, free tier |
| Media storage | Cloudflare R2 | Zero egress fees, global CDN |
| OTP provider | Firebase Auth → MSG91 | Fast MVP, migrate at Phase 2 |
| Push notifications | OneSignal | Free to 10k, single SDK |
| Real-time | SSE (not WebSockets) | One-directional — simpler for Flicker |
| Transcription | OpenAI Whisper API | Best accuracy, simplest integration |
| Payments | Razorpay | Best Flutter SDK, startup program |
| Hosting | Railway | Zero DevOps, GitHub auto-deploy |
| Soft delete | On all user content | Emotional data must never be permanently lost |

### Streak Update Logic (Critical — Get Right from Day 1)

```typescript
async updateStreak(connectionId: string, entryDate: Date): Promise<void> {
  const conn = await this.db.findConnection(connectionId);
  const today = toISTDate(entryDate); // always work in IST date

  if (!conn.streak_last_date) {
    // First entry ever
    await this.db.updateConnection(connectionId, {
      streak_count: 1, streak_last_date: today,
      streak_started_at: today, longest_streak: 1,
      diary_weather: 'cloudy',
    });
    return;
  }

  const daysSinceLast = differenceInCalendarDays(today, conn.streak_last_date);

  if (daysSinceLast === 0) {
    return; // Already recorded today — no change
  } else if (daysSinceLast === 1) {
    // Consecutive day — extend streak
    const newStreak = conn.streak_count + 1;
    await this.db.updateConnection(connectionId, {
      streak_count: newStreak,
      streak_last_date: today,
      longest_streak: Math.max(newStreak, conn.longest_streak),
      diary_weather: computeWeather(newStreak),
    });
    await this.checkAndFireMilestones(connectionId, newStreak);
  } else {
    // Streak broken — reset to 1 (new entry starts a new streak)
    await this.db.updateConnection(connectionId, {
      streak_count: 1, streak_last_date: today,
      streak_started_at: today, diary_weather: 'partly_cloudy',
    });
  }
}

function computeWeather(streak: number): 'sunny'|'partly_cloudy'|'cloudy'|'dormant' {
  if (streak >= 30) return 'sunny';
  if (streak >= 14) return 'partly_cloudy';
  if (streak >= 3)  return 'cloudy';
  return 'dormant';
}

async checkAndFireMilestones(connectionId: string, streak: number): Promise<void> {
  const milestones = [7, 30, 60, 100, 200, 365];
  if (!milestones.includes(streak)) return;

  const existing = await this.db.query(
    `SELECT 1 FROM streak_milestones WHERE connection_id=$1 AND milestone_days=$2`,
    [connectionId, streak]
  );
  if (existing.rows.length) return; // already achieved

  await this.db.query(
    `INSERT INTO streak_milestones (connection_id, milestone_days) VALUES ($1, $2)`,
    [connectionId, streak]
  );
  // Push celebration notification to both users
  const conn = await this.db.findConnection(connectionId);
  await this.notifQueue.add('push', {
    userId: conn.user_a_id, type: 'milestone',
    data: { connection_id: connectionId, days: streak }
  });
  await this.notifQueue.add('push', {
    userId: conn.user_b_id, type: 'milestone',
    data: { connection_id: connectionId, days: streak }
  });
}
```

---

*Saanjh Backend Architecture Document — May 2026*
*Maintained by: solo developer. Review and update before each major phase.*

