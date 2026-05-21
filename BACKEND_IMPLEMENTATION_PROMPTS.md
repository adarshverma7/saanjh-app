# Saanjh Backend — Implementation Prompts
**Execute these prompts in order. Each prompt is self-contained and builds on the previous.**
**Stack: NestJS + TypeScript + PostgreSQL (Supabase) + Cloudflare R2**

---

## HOW TO USE THIS FILE

- Give each numbered prompt directly to Claude Code.
- Complete and verify one prompt before moving to the next.
- Each prompt references specific file paths, class names, and schemas from `BACKEND_ARCHITECTURE.md`.
- The backend lives in a separate repo: `saanjh-backend/` (create alongside the Flutter project).

---

## PROMPT 01 — Project Initialization & Folder Structure

```
Create a new NestJS backend project for Saanjh. Do the following exactly:

1. INITIALIZE THE PROJECT
   - Run: npx @nestjs/cli new saanjh-backend --package-manager npm
   - Language: TypeScript (strict mode)
   - Delete the default src/app.controller.spec.ts and src/app.service.ts

2. INSTALL ALL DEPENDENCIES
   Core:
     npm install @nestjs/config @nestjs/typeorm typeorm pg
     npm install @nestjs/passport passport passport-jwt
     npm install @nestjs/jwt
     npm install @nestjs/bull bull
     npm install @nestjs/schedule
     npm install @nestjs/event-emitter
     npm install class-validator class-transformer
     npm install helmet
     npm install @aws-sdk/client-s3 @aws-sdk/s3-request-presigner
     npm install openai
     npm install axios
     npm install date-fns date-fns-tz
     npm install crypto (built-in)
   
   Dev:
     npm install -D @types/passport-jwt @types/bull @types/pg
     npm install -D @nestjs/testing jest ts-jest

3. CREATE THE EXACT FOLDER STRUCTURE inside src/:

   src/
     auth/
       dto/
       guards/
       strategies/
       auth.controller.ts
       auth.service.ts
       auth.module.ts
     users/
       dto/
       users.controller.ts
       users.service.ts
       users.module.ts
     connections/
       dto/
       connections.controller.ts
       connections.service.ts
       connections.module.ts
     entries/
       dto/
       entries.controller.ts
       entries.service.ts
       entries.module.ts
     flicker/
       dto/
       flicker.controller.ts
       flicker.service.ts
       flicker.module.ts
       events.service.ts
     memory-tree/
       memory-tree.controller.ts
       memory-tree.service.ts
       memory-tree.module.ts
     on-this-day/
       on-this-day.controller.ts
       on-this-day.service.ts
       on-this-day.module.ts
     memory-jar/
       memory-jar.controller.ts
       memory-jar.service.ts
       memory-jar.module.ts
     streaks/
       streaks.controller.ts
       streaks.service.ts
       streaks.module.ts
     journal/
       dto/
       journal.controller.ts
       journal.service.ts
       journal.module.ts
     notifications/
       dto/
       notifications.controller.ts
       notifications.service.ts
       notifications.module.ts
       notification-cron.service.ts
     occasions/
       dto/
       occasions.controller.ts
       occasions.service.ts
       occasions.module.ts
     memory-books/
       dto/
       memory-books.controller.ts
       memory-books.service.ts
       memory-books.module.ts
     search/
       search.controller.ts
       search.service.ts
       search.module.ts
     admin/
       admin.controller.ts
       admin.service.ts
       admin.module.ts
     shared/
       database/
         database.module.ts
         entities/   (all TypeORM entity files go here)
       storage/
         storage.service.ts
         storage.module.ts
       config/
         configuration.ts
         env.validation.ts
     workers/
       transcription.worker.ts
       notification.worker.ts
       pdf.worker.ts
       cleanup.worker.ts
     middleware/
       activity.middleware.ts
     decorators/
       current-user.decorator.ts
     guards/
       jwt-auth.guard.ts
       connection-member.guard.ts
       admin.guard.ts
     app.module.ts
     main.ts

4. CONFIGURE main.ts:
   - Global validation pipe: new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true })
   - Global prefix: app.setGlobalPrefix('v1')
   - Helmet: app.use(helmet())
   - CORS: app.enableCors({ origin: process.env.ALLOWED_ORIGINS?.split(',') ?? '*' })
   - Listen on port: process.env.PORT ?? 3000
   - Graceful shutdown: app.enableShutdownHooks()

5. CREATE .env.example with these keys (no values):
   DATABASE_URL=
   JWT_PRIVATE_KEY=
   JWT_PUBLIC_KEY=
   REFRESH_TOKEN_SECRET=
   PHONE_HASH_SALT=
   R2_ACCESS_KEY_ID=
   R2_SECRET_ACCESS_KEY=
   R2_BUCKET_NAME=
   R2_ENDPOINT=
   R2_PUBLIC_CDN=
   OPENAI_API_KEY=
   ONESIGNAL_APP_ID=
   ONESIGNAL_API_KEY=
   RAZORPAY_KEY_ID=
   RAZORPAY_KEY_SECRET=
   MSG91_AUTH_KEY=
   FIREBASE_PROJECT_ID=
   FIREBASE_PRIVATE_KEY=
   FIREBASE_CLIENT_EMAIL=
   ADMIN_JWT_SECRET=
   ALLOWED_ORIGINS=
   NODE_ENV=

6. CREATE src/shared/config/configuration.ts that exports a config function
   loading all env vars above with defaults where safe.

7. CREATE src/shared/config/env.validation.ts using Joi to validate that
   DATABASE_URL, JWT_PRIVATE_KEY, JWT_PUBLIC_KEY, PHONE_HASH_SALT,
   R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME, R2_ENDPOINT
   are present in production. In development, allow them to be optional.

8. CREATE .github/workflows/deploy.yml:
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

9. CREATE Procfile (for Railway):
   web: npm run migration:run && npm run start:prod

10. Verify: npm run build runs without errors.
```

---

## PROMPT 02 — Database Entities & Migrations

```
Create all TypeORM entities and the initial migration for Saanjh. 
All entity files go in src/shared/database/entities/.

1. CREATE src/shared/database/database.module.ts:
   - Import TypeOrmModule.forRootAsync using ConfigService
   - Connect to DATABASE_URL (Supabase PostgreSQL connection string)
   - Set synchronize: false (always use migrations, never auto-sync)
   - Set ssl: { rejectUnauthorized: false } for Supabase
   - Set logging: process.env.NODE_ENV === 'development'
   - entities: [__dirname + '/entities/*.entity{.ts,.js}']
   - migrations: [__dirname + '/migrations/*{.ts,.js}']

2. CREATE these TypeORM entity files. Each must match the exact schema
   from BACKEND_ARCHITECTURE.md Section 3:

   user.entity.ts — columns: id, phone, phone_hash, name, avatar_key,
     language, timezone, date_of_birth, is_onboarded, is_verified,
     is_active, last_active_at, created_at, updated_at, deleted_at

   diary-connection.entity.ts — columns: id, user_a_id, user_b_id,
     relationship_type, initiated_by, status, name_for_a, name_for_b,
     streak_count, longest_streak, streak_last_date, streak_started_at,
     diary_weather, last_entry_at, total_entry_count, created_at, updated_at
     NOTE: Add @Check("user_a_id < user_b_id") constraint.
     NOTE: Add @Unique(['user_a_id', 'user_b_id']) constraint.

   diary-entry.entity.ts — columns: id, connection_id, author_id,
     entry_type ('voice'|'video'), media_key, duration_seconds,
     file_size_bytes, thumbnail_key, transcription,
     transcription_status ('pending'|'processing'|'done'|'failed'|'skipped'),
     mood, is_starred, starred_at, play_count, recorded_at,
     created_at, updated_at, deleted_at

   flicker-event.entity.ts — columns: id, connection_id, sender_id,
     receiver_id, sent_at, delivered_at, is_mutual, mutual_at,
     mutual_window_secs (default 300)

   personal-journal-entry.entity.ts — columns: id, user_id, entry_type,
     media_key, text_content, duration_seconds, mood, is_starred,
     recorded_at, created_at, deleted_at

   streak-milestone.entity.ts — columns: id, connection_id,
     milestone_days, achieved_at, seen_by_a, seen_by_b
     NOTE: Add @Unique(['connection_id', 'milestone_days']) constraint.

   notification.entity.ts — columns: id, user_id, type, title, body,
     data (jsonb), is_read, read_at, push_status, push_error, created_at

   notification-preference.entity.ts — columns: user_id (PK),
     new_entry, flicker_received, streak_reminder, streak_reminder_time,
     occasion_reminders, morning_ritual, morning_ritual_time,
     quiet_hours_start, quiet_hours_end, updated_at

   occasion.entity.ts — columns: id, connection_id, created_by,
     occasion_type, occasion_name, occasion_date, is_recurring,
     remind_days_before, last_reminded_year, created_at

   occasion-ai-message.entity.ts — columns: id, connection_id,
     occasion_id, occasion_type, prompt_used, generated_text,
     language, model_used, used_at, created_at

   memory-book-order.entity.ts — columns: id, connection_id, ordered_by,
     order_type ('self'|'gift'), gift_recipient_name, gift_recipient_phone,
     date_from, date_to, entry_count, amount_paise, currency,
     razorpay_order_id, razorpay_payment_id, payment_status, paid_at,
     pdf_key, print_status, shipping_address (jsonb), tracking_number,
     created_at, updated_at

   invite.entity.ts — columns: id, inviter_id, invite_code, invited_phone,
     invited_phone_hash, relationship_type, connection_name, status,
     accepted_by, accepted_at, click_count, expires_at, created_at

   device-session.entity.ts — columns: id, user_id, device_id,
     device_type, fcm_token, app_version, os_version, is_active,
     last_used_at, created_at
     NOTE: Add @Unique(['user_id', 'device_id']) constraint.

   otp-verification.entity.ts — columns: id, phone, otp_hash, purpose,
     attempt_count, is_used, expires_at, created_at

   memory-tree-cache.entity.ts — columns: connection_id (PK),
     monthly_data (jsonb), total_entries, active_months, tree_health
     (decimal 3,2), last_computed_at

   feature-flag.entity.ts — columns: key (PK varchar 100), is_enabled,
     rollout_percentage (0-100), description, updated_at

   audit-log.entity.ts — columns: id (bigint auto), user_id, action,
     resource_type, resource_id, metadata (jsonb), ip_address, created_at

   rate-limit-counter.entity.ts — columns: key (PK varchar 200),
     count, window_start, updated_at

3. CREATE the initial migration file that creates all tables with exact
   column types, constraints, and indexes matching BACKEND_ARCHITECTURE.md.
   Key indexes to include:
   - idx_users_phone_hash ON users(phone_hash)
   - idx_users_last_active ON users(last_active_at) WHERE deleted_at IS NULL
   - idx_conn_a ON diary_connections(user_a_id) WHERE status = 'active'
   - idx_conn_b ON diary_connections(user_b_id) WHERE status = 'active'
   - idx_entries_thread ON diary_entries(connection_id, recorded_at DESC) WHERE deleted_at IS NULL
   - idx_entries_starred ON diary_entries(connection_id, starred_at DESC) WHERE is_starred = true AND deleted_at IS NULL
   - idx_entries_anniversary ON diary_entries(connection_id, EXTRACT(MONTH FROM recorded_at)::INT, EXTRACT(DAY FROM recorded_at)::INT) WHERE deleted_at IS NULL
   - idx_entries_monthly ON diary_entries(connection_id, DATE_TRUNC('month', recorded_at)) WHERE deleted_at IS NULL
   - idx_entries_fts ON diary_entries USING GIN(to_tsvector('english', COALESCE(transcription, ''))) WHERE deleted_at IS NULL
   - idx_flicker_connection ON flicker_events(connection_id, sent_at DESC)
   - idx_flicker_receiver ON flicker_events(receiver_id, sent_at DESC)
   - idx_flicker_window ON flicker_events(sender_id, receiver_id, sent_at DESC)
   - idx_notif_user_unread ON notifications(user_id, created_at DESC) WHERE is_read = false
   - idx_invites_code ON invites(invite_code)
   - idx_invites_phone_hash ON invites(invited_phone_hash) WHERE status = 'pending'
   - idx_sessions_user_active ON device_sessions(user_id) WHERE is_active = true
   - idx_otp_phone ON otp_verifications(phone, created_at DESC)
   - idx_occasions_upcoming ON occasions using expression index on month/day extraction
   - idx_audit_user ON audit_logs(user_id, created_at DESC)

4. Add npm scripts to package.json:
   "migration:run": "typeorm migration:run -d src/shared/database/data-source.ts"
   "migration:revert": "typeorm migration:revert -d src/shared/database/data-source.ts"
   "migration:generate": "typeorm migration:generate -d src/shared/database/data-source.ts"

5. Seed feature_flags table with these initial rows:
   { key: 'video_entries', is_enabled: false, rollout_percentage: 0 }
   { key: 'occasion_ai', is_enabled: false, rollout_percentage: 0 }
   { key: 'memory_book', is_enabled: false, rollout_percentage: 0 }
   { key: 'transcription', is_enabled: true, rollout_percentage: 100 }

6. Verify: npm run migration:run completes without errors against a local
   PostgreSQL or Supabase dev project.
```

---

## PROMPT 03 — Shared Services: Storage, Config, Middleware

```
Build the foundational shared services used by every module.

1. CREATE src/shared/storage/storage.service.ts — Cloudflare R2 service:

   The service must use @aws-sdk/client-s3 (R2 is S3-compatible).
   Initialize S3Client with:
     endpoint: process.env.R2_ENDPOINT
     region: 'auto'
     credentials: { accessKeyId: R2_ACCESS_KEY_ID, secretAccessKey: R2_SECRET_ACCESS_KEY }

   Implement these methods:
   
   async getPresignedUploadUrl(key: string, contentType: string, expiresIn = 900): Promise<string>
     - Uses PutObjectCommand + getSignedUrl
     - expiresIn: 900 seconds (15 minutes)
   
   async getSignedDownloadUrl(key: string, expiresIn = 3600): Promise<string>
     - Uses GetObjectCommand + getSignedUrl
     - expiresIn: 3600 seconds (1 hour)
   
   async objectExists(key: string): Promise<boolean>
     - Uses HeadObjectCommand, returns true if 200, false if 404
   
   async deleteObject(key: string): Promise<void>
     - Uses DeleteObjectCommand
   
   async getObjectBuffer(key: string): Promise<Buffer>
     - Uses GetObjectCommand, reads stream to buffer
     - Used by transcription worker to download audio
   
   Media key generator helpers (static methods):
   static voiceKey(connectionId: string, entryId: string): string
     → returns: `entries/shared/${connectionId}/${year}/${month}/${entryId}.m4a`
   static videoKey(connectionId: string, entryId: string): string
     → returns: `entries/shared/${connectionId}/${year}/${month}/${entryId}.mp4`
   static thumbnailKey(connectionId: string, entryId: string): string
     → returns: `entries/thumbs/${connectionId}/${year}/${month}/${entryId}.jpg`
   static journalKey(userId: string, entryId: string): string
     → returns: `entries/journal/${userId}/${year}/${month}/${entryId}.m4a`
   static avatarKey(userId: string): string
     → returns: `avatars/${userId}/${Date.now()}.jpg`
   static bookKey(orderId: string): string
     → returns: `books/${orderId}/memory_book.pdf`

2. CREATE src/middleware/activity.middleware.ts:
   - Implements NestMiddleware
   - On every authenticated request: fire-and-forget update of users.last_active_at
   - Must NOT await — just call repo.update() and ignore the promise
   - Only runs when req.user?.id is present (JWT already decoded by guard)
   - Apply this middleware globally in AppModule for all routes under /v1/

3. CREATE src/decorators/current-user.decorator.ts:
   - @CurrentUser() decorator that extracts user from request
   - Returns the full user object attached by JwtStrategy

4. CREATE src/guards/jwt-auth.guard.ts:
   - Extends AuthGuard('jwt')
   - On unauthorized: throws UnauthorizedException with code 'INVALID_TOKEN'

5. CREATE src/guards/connection-member.guard.ts — the core privacy boundary:
   - Implements CanActivate
   - Reads connectionId from request.params.id
   - Reads userId from request.user.id
   - Queries: SELECT 1 FROM diary_connections
     WHERE id = $connectionId
     AND status = 'active'
     AND (user_a_id = $userId OR user_b_id = $userId)
   - If not found: throws ForbiddenException with code 'NOT_CONNECTION_MEMBER'
   - CRITICAL: This guard must be applied to every diary, entry, flicker,
     memory-tree, occasion, and memory-jar endpoint.

6. CREATE src/guards/admin.guard.ts:
   - Validates a separate ADMIN_JWT_SECRET (not the user JWT secret)
   - Reads from Authorization header: "Bearer <admin_token>"
   - Used only on /v1/admin/* routes
   - On failure: throws UnauthorizedException

7. CREATE src/shared/helpers/phone.helper.ts:
   normalizePhone(raw: string): string
     - Strip all non-digit characters
     - If 10 digits: prepend +91
     - If 12 digits starting with 91: prepend +
     - Throw BadRequestException('INVALID_PHONE') if result is not 12-13 chars
   
   hashPhone(normalized: string): string
     - HMAC-SHA256 using PHONE_HASH_SALT from env
     - Returns hex digest string
   
   hashOtp(otp: string): string
     - SHA-256 of the OTP string
     - Returns hex digest

8. CREATE src/shared/helpers/pagination.helper.ts:
   encodeCursor(recordedAt: Date, id: string): string
     - base64-encode JSON: { t: recordedAt.toISOString(), i: id }
   
   decodeCursor(cursor: string): { recordedAt: Date; id: string } | null
     - base64-decode, parse JSON, return null on any error
   
   buildCursorWhere(cursor: string | undefined): string
     - Returns SQL WHERE clause fragment for cursor-based pagination
     - Example: "(recorded_at, id) < ($t, $id)"

9. Verify: All services export correctly, no circular dependencies.
```

---

## PROMPT 04 — Auth Module (OTP + JWT + Sessions)

```
Implement complete authentication for Saanjh. Phone OTP → JWT tokens → device sessions.

REFERENCE: BACKEND_ARCHITECTURE.md Section 9 (Security & Trust) and Section 4 (Auth APIs).

1. CREATE src/auth/dto/send-otp.dto.ts:
   class SendOtpDto { @IsString() @Matches(/^\+91[6-9]\d{9}$/) phone: string }

2. CREATE src/auth/dto/verify-otp.dto.ts:
   class VerifyOtpDto { phone: string; otp: string (6 digits) }

3. CREATE src/auth/dto/refresh-token.dto.ts:
   class RefreshTokenDto { refresh_token: string }

4. CREATE src/auth/strategies/jwt.strategy.ts:
   - Uses passport-jwt with RS256 algorithm
   - Public key from process.env.JWT_PUBLIC_KEY
   - Extracts token from Authorization: Bearer header
   - validate(payload): queries users table by payload.sub
   - Attaches full user + session_id + device_id to request
   - Throws UnauthorizedException if user not found or deleted_at is set

5. CREATE src/auth/auth.service.ts with these methods:

   async sendOtp(phone: string): Promise<void>
     RATE LIMITING:
       - Check rate_limit_counters: key = 'otp:${phone}', window = 10 min, max = 3
       - Check rate_limit_counters: key = 'otp_ip:${ip}', window = 1 hour, max = 15
       - If exceeded: throw TooManyRequestsException('OTP_RATE_LIMIT')
     OTP GENERATION:
       - Generate 6-digit random OTP: Math.floor(100000 + Math.random() * 900000).toString()
       - Hash it: SHA-256(otp) using phone.helper.ts hashOtp()
       - Store in otp_verifications: { phone, otp_hash, purpose: 'login', expires_at: now+10min }
       - Invalidate any previous unused OTPs for this phone (set is_used=true)
     SMS DELIVERY (MVP):
       - Log OTP to console in development (never in production)
       - In production: call MSG91 API or Firebase Auth OTP
       - Wrap in try/catch — if SMS fails, throw ServiceUnavailableException('SMS_FAILED')

   async verifyOtp(phone: string, otp: string, deviceInfo: DeviceInfo): Promise<AuthTokens>
     VALIDATION:
       - Find latest valid OTP: WHERE phone=$phone AND is_used=false AND expires_at > now()
       - If not found: throw UnauthorizedException('OTP_EXPIRED')
       - Check attempt_count < 5, else throw TooManyRequestsException('TOO_MANY_ATTEMPTS')
       - Compare SHA-256(otp) === stored otp_hash
       - If wrong: increment attempt_count, throw UnauthorizedException('INVALID_OTP')
       - Mark OTP as used: is_used = true
     USER CREATION/LOOKUP:
       - Find or create user by phone
       - If new user: compute phone_hash, set is_verified=true
       - If existing user with deleted_at set: throw ForbiddenException('ACCOUNT_DELETED')
     SESSION:
       - Upsert device_sessions: { user_id, device_id, device_type, app_version, fcm_token? }
       - Enforce max 5 active devices: if 6th device, deactivate oldest last_used_at device
     TOKENS:
       - Generate access token: RS256 JWT, payload = { sub: user.id, session_id, device_id }
         exp: 15 minutes
       - Generate refresh token: 64 random bytes as hex string
       - Store refresh token HASH (SHA-256) in device_sessions.refresh_token_hash
       - Return: { access_token, refresh_token, is_new_user: boolean, user: UserProfile }

   async refreshToken(refreshToken: string, deviceId: string): Promise<AuthTokens>
     - Hash the incoming token: SHA-256(refreshToken)
     - Find session WHERE refresh_token_hash = $hash AND device_id = $deviceId AND is_active = true
     - If not found: throw UnauthorizedException('INVALID_TOKEN')
     - ROTATION: generate new refresh token, update hash in DB, invalidate old immediately
     - Issue new access token
     - Return: { access_token, refresh_token }

   async logout(userId: string, deviceId: string): Promise<void>
     - Set device_sessions.is_active = false WHERE user_id=$userId AND device_id=$deviceId
     - Nullify refresh_token_hash

   async getSessions(userId: string): Promise<DeviceSession[]>
     - Return all active sessions for user (for "manage devices" screen)

   async revokeSession(userId: string, sessionId: string): Promise<void>
     - Set is_active=false WHERE id=$sessionId AND user_id=$userId

6. CREATE src/auth/auth.controller.ts:
   POST /auth/otp/send      → sendOtp (rate limited)
   POST /auth/otp/verify    → verifyOtp
   POST /auth/token/refresh → refreshToken
   POST /auth/logout        → logout (JWT required)
   GET  /auth/sessions      → getSessions (JWT required)
   DELETE /auth/sessions/:id → revokeSession (JWT required)
   POST /auth/account/delete/request → request account deletion OTP
   POST /auth/account/delete/confirm → confirm deletion with OTP

7. ACCOUNT DELETION flow in auth.service.ts:
   async requestAccountDeletion(userId: string): Promise<void>
     - Send OTP with purpose: 'delete_account'
   
   async confirmAccountDeletion(userId: string, otp: string): Promise<void>
     - Verify OTP (same flow as login but purpose='delete_account')
     - Set users.deleted_at = now()
     - Set all device_sessions.is_active = false
     - Queue a job (Bull) to run hard delete after 30 days
     - Log to audit_logs: { action: 'account.delete_requested', user_id }

8. Apply @UseGuards(JwtAuthGuard) to all endpoints except send/verify/refresh.

9. All error responses must follow format:
   { "error": { "code": "INVALID_OTP", "message": "OTP is incorrect or expired" } }
   Create a custom exception filter in src/filters/http-exception.filter.ts that
   transforms all HttpExceptions to this format. Apply it globally in main.ts.

10. Write unit tests for auth.service.ts covering:
    - Rate limit enforcement
    - OTP expiry
    - Wrong OTP increments attempt_count
    - Correct OTP issues tokens
    - Refresh token rotation invalidates old token
```

---

## PROMPT 05 — Users & Onboarding Module

```
Implement user profile management and onboarding flow.

REFERENCE: BACKEND_ARCHITECTURE.md Section 4 (Onboarding APIs, Settings APIs).

1. CREATE src/users/dto/update-profile.dto.ts:
   class UpdateProfileDto {
     @IsOptional() @IsString() @MaxLength(100) name?: string;
     @IsOptional() @IsIn(['en', 'hi']) language?: string;
     @IsOptional() @IsDateString() date_of_birth?: string;
     @IsOptional() @IsString() timezone?: string;
   }

2. CREATE src/users/users.service.ts:

   async getProfile(userId: string): Promise<UserProfile>
     - Fetch user by id WHERE deleted_at IS NULL
     - If avatar_key exists: generate signed URL via StorageService (1h expiry)
     - Return: { id, name, phone (masked), language, timezone, avatar_url, is_onboarded, last_active_at }

   async updateProfile(userId: string, dto: UpdateProfileDto): Promise<UserProfile>
     - Update users table
     - If name changed and user has connections: update name_for_* in diary_connections is NOT done here
       (connection names are independent — user chose them separately)

   async getAvatarUploadUrl(userId: string): Promise<{ upload_url: string; avatar_key: string }>
     - Generate a unique avatar_key using StorageService.avatarKey(userId)
     - Get pre-signed PUT URL (15 min expiry)
     - Return both

   async updateAvatar(userId: string, avatarKey: string): Promise<UserProfile>
     - Verify object exists in R2: storageService.objectExists(avatarKey)
     - If not found: throw BadRequestException('AVATAR_NOT_UPLOADED')
     - Delete old avatar from R2 if it exists (fire-and-forget)
     - Update users.avatar_key

   async completeOnboarding(userId: string): Promise<void>
     - Set is_onboarded = true, updated_at = now()
     - Log to audit_logs: { action: 'user.onboarding_complete' }

   async getOnboardingStatus(userId: string): Promise<OnboardingStatus>
     - Return: { step: 'profile'|'connection'|'complete', profile_complete, has_connection }
     - profile_complete: name is not null
     - has_connection: EXISTS SELECT in diary_connections WHERE (user_a_id=$1 OR user_b_id=$1) AND status='active'
     - step logic: if !profile_complete → 'profile', if !has_connection → 'connection', else 'complete'

   async getSettings(userId: string): Promise<UserSettings>
     - Return user fields + notification preferences joined

   async updateSettings(userId: string, settings: Partial<UserSettings>): Promise<UserSettings>
     - Update relevant user fields

   async getFeatureFlags(userId: string): Promise<Record<string, boolean>>
     - Fetch all feature_flags
     - For each flag: is_enabled AND (rollout_percentage === 100 OR
       deterministicRollout(userId, key) < rollout_percentage)
     - deterministicRollout: SHA-256(userId + key) mod 100 (consistent per user)

   async requestDataExport(userId: string): Promise<void>
     - Queue a Bull job: 'export_user_data' with userId
     - Log to audit_logs
     - Return immediately (user gets notification when ready)

3. CREATE src/users/users.controller.ts:
   GET    /onboarding/status        → getOnboardingStatus
   PUT    /onboarding/profile       → updateProfile
   POST   /onboarding/avatar/upload-url → getAvatarUploadUrl
   PATCH  /onboarding/avatar        → updateAvatar
   POST   /onboarding/complete      → completeOnboarding
   GET    /settings                 → getSettings
   PATCH  /settings                 → updateSettings
   GET    /settings/feature-flags   → getFeatureFlags
   GET    /settings/data-export     → requestDataExport
   All routes: @UseGuards(JwtAuthGuard)

4. APPLY ActivityMiddleware to the users module routes so last_active_at
   updates on every settings/profile fetch.

5. The masked phone format: show only last 4 digits — "+91XXXXXX" + last4
   Never return the full phone number in any API response.
```

---

## PROMPT 06 — Diary Connections & Invite Module

```
Implement the 1-to-1 diary connection system and WhatsApp invite flow.
This is how parents get onboarded — the most critical user acquisition flow.

REFERENCE: BACKEND_ARCHITECTURE.md Section 4 (Connection APIs, Invite APIs) and Section 5 (Invite & Contact System).

1. CREATE src/connections/dto/create-invite.dto.ts:
   class CreateInviteDto {
     @IsOptional() @Matches(E164_REGEX) phone?: string;
     @IsIn(['parent_child','partners','siblings','friends']) relationship_type: string;
     @IsString() @MaxLength(100) connection_name: string;
   }

2. CREATE src/connections/dto/accept-invite.dto.ts:
   class AcceptInviteDto {
     @IsString() @Length(6,12) invite_code: string;
     @IsString() @MaxLength(100) connection_name: string;
   }

3. CREATE src/connections/connections.service.ts:

   async createInvite(inviterId: string, dto: CreateInviteDto): Promise<InviteResult>
     RATE LIMITS:
       - Max 10 invites per user per day
       - Max 3 pending invites at once for this user
       - If inviter account < 24 hours old: throw ForbiddenException('ACCOUNT_TOO_NEW')
     DUPLICATE CHECK:
       - If dto.phone provided: check no active connection already exists between these phones
     CODE GENERATION:
       - Generate 8-char alphanumeric invite_code (no 0,O,1,I):
         chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
         Use crypto.randomBytes(8), map each byte to chars[byte % 32]
     PHONE HASHING:
       - If phone provided: normalize + hash using phone.helper.ts
     DEEP LINK:
       - deep_link_url = https://saanjh.app/join/${invite_code}
     WHATSAPP MESSAGE (relationship-aware):
       - parent_child (inviting parent): "Maa/Papa, main Saanjh use kar raha hoon..."
       - parent_child (inviting child): "Beta/Beti, let me share voice notes with you..."
       - partners: "I want to share little moments with you every day..."
       - siblings: "Let's stay connected with voice notes..."
       - Include deep link at end of each message
     STORE invite row with expires_at = now() + 7 days
     RETURN: { invite_id, invite_code, deep_link, whatsapp_message, expires_at }

   async getInviteDetails(code: string): Promise<PublicInviteDetails>
     - Find invite WHERE invite_code=$code AND status='pending' AND expires_at > now()
     - If not found: throw NotFoundException('INVITE_NOT_FOUND')
     - If expired: throw GoneException('INVITE_EXPIRED')
     - Increment click_count (fire-and-forget)
     - Return: { valid: true, inviter_name, relationship_type, expires_at }
     - IMPORTANT: do not reveal inviter phone or id

   async acceptInvite(acceptorId: string, code: string, connectionName: string): Promise<DiaryConnection>
     VALIDATION:
       - Find invite by code (same as getInviteDetails but throw if already accepted)
       - If acceptor === inviter: throw BadRequestException('CANNOT_ACCEPT_OWN_INVITE')
       - If active connection already exists between these two users: throw ConflictException('ALREADY_CONNECTED')
     PAIR ORDERING (critical):
       - Determine user_a_id and user_b_id: smaller UUID goes in user_a_id
       - This enforces the CHECK(user_a_id < user_b_id) constraint and uniqueness
     CREATE connection:
       - Insert diary_connections row with status='active'
       - name_for_a: if inviter is user_a → invite.connection_name, else dto.connection_name
       - name_for_b: mirror of above
       - Set invited phone's invite status = 'accepted', accepted_by = acceptorId
     CREATE notification_preferences row for both users (with defaults)
     LOG audit: { action: 'connection.created', resource_id: connection.id }
     RETURN full DiaryConnection

   async getConnections(userId: string): Promise<ConnectionListItem[]>
     - Find all connections WHERE (user_a_id=$1 OR user_b_id=$1) AND status='active'
     - For each connection:
         partner = the OTHER user (not the requesting user)
         connection_name = name_for_a if requester is user_a, else name_for_b
         unread_count = COUNT of diary_entries WHERE connection_id=$id
           AND author_id != $userId AND play_count = 0 AND deleted_at IS NULL
         Generate partner avatar_url (signed, 1h) if avatar_key exists
     - Order by last_entry_at DESC NULLS LAST

   async getConnection(userId: string, connectionId: string): Promise<DiaryConnectionDetail>
     - Validate ownership (ConnectionMemberGuard handles this, but double-check)
     - Return full connection with partner profile + health stats

   async getConnectionHealth(userId: string, connectionId: string): Promise<ConnectionHealth>
     - Return: { streak_count, diary_weather, total_entries, entries_this_week,
                 last_entry_at, days_since_last_entry }
     - entries_this_week: COUNT WHERE recorded_at >= now() - 7 days

   async renameConnection(userId: string, connectionId: string, name: string): Promise<void>
     - Update name_for_a if user is user_a, else name_for_b

   async getMyInvites(userId: string): Promise<Invite[]>
     - Return pending invites sent by this user with status

   async cancelInvite(userId: string, inviteId: string): Promise<void>
     - Set invite.status = 'cancelled' WHERE id=$inviteId AND inviter_id=$userId

4. PENDING INVITE AUTO-MATCH on user signup:
   In auth.service.ts, after creating a new user, call:
   connectionsService.checkPendingInvite(user.phone_hash, user.id)
   
   checkPendingInvite(phoneHash: string, newUserId: string): Promise<void>
     - SELECT FROM invites WHERE invited_phone_hash = $phoneHash AND status = 'pending'
     - If found: auto-call acceptInvite with a system connection_name derived from relationship_type
     - This is how parents who click the WhatsApp link get auto-connected on signup

5. CREATE src/connections/connections.controller.ts:
   POST   /connections/invite            → createInvite (JWT required, rate limited)
   GET    /connections/invite/:code      → getInviteDetails (no auth — for pre-signup)
   POST   /connections/invite/:code/accept → acceptInvite (JWT required)
   GET    /connections                   → getConnections (JWT required)
   GET    /connections/:id               → getConnection (JWT + ConnectionMemberGuard)
   GET    /connections/:id/health        → getConnectionHealth (JWT + ConnectionMemberGuard)
   PATCH  /connections/:id/name          → renameConnection (JWT + ConnectionMemberGuard)
   GET    /invites                       → getMyInvites (JWT required)
   DELETE /invites/:id                   → cancelInvite (JWT required)
```

---

## PROMPT 07 — Diary Entries Module (Upload, CRUD, Playback)

```
Implement the core diary entry system: voice upload, storage, thread, soft delete.
This is the heart of Saanjh — voice memories must never be lost.

REFERENCE: BACKEND_ARCHITECTURE.md Section 4 (Diary Entry APIs) and Section 8 (Media Handling).

1. CREATE src/entries/dto/upload-url.dto.ts:
   class UploadUrlDto {
     @IsIn(['voice','video']) entry_type: string;
     @IsIn(['m4a','mp4']) file_extension: string;
     @IsInt() @Min(1) @Max(20) duration_seconds: number;
     @IsInt() @Min(1000) @Max(10_000_000) file_size_bytes: number;
   }

2. CREATE src/entries/dto/create-entry.dto.ts:
   class CreateEntryDto {
     @IsString() media_key: string;
     @IsIn(['voice','video']) entry_type: string;
     @IsInt() @Min(1) @Max(20) duration_seconds: number;
     @IsOptional() @IsIn(['happy','calm','thoughtful','missing','excited']) mood?: string;
     @IsOptional() @IsDateString() recorded_at?: string;
   }

3. CREATE src/entries/dto/list-entries.dto.ts:
   class ListEntriesDto {
     @IsOptional() @IsInt() @Min(1) @Max(50) limit?: number = 20;
     @IsOptional() @IsString() cursor?: string;
     @IsOptional() @IsIn(['all','voice','video','starred']) filter?: string = 'all';
   }

4. CREATE src/entries/entries.service.ts:

   async getUploadUrl(userId: string, connectionId: string, dto: UploadUrlDto): Promise<UploadUrlResult>
     RATE LIMIT: max 30 uploads per connection per day (key: 'upload:${connectionId}:${date}')
     GENERATE entry ID upfront: const entryId = randomUUID()
     BUILD media key:
       - voice: StorageService.voiceKey(connectionId, entryId)
       - video: StorageService.videoKey(connectionId, entryId)
     GET pre-signed PUT URL from StorageService (15 min expiry)
     RETURN: { upload_url, media_key, entry_id, expires_in: 900 }

   async createEntry(userId: string, connectionId: string, dto: CreateEntryDto): Promise<DiaryEntry>
     VERIFY UPLOAD:
       - storageService.objectExists(dto.media_key)
       - If false: throw BadRequestException('MEDIA_NOT_UPLOADED')
       - Check media_key belongs to this connectionId (parse the key path)
     INSERT diary_entry row:
       - author_id = userId
       - recorded_at = dto.recorded_at ?? now()
     UPDATE diary_connections:
       - last_entry_at = now()
       - total_entry_count++ (use UPDATE ... SET total_entry_count = total_entry_count + 1)
     UPDATE STREAK (call streaksService.onNewEntry(connectionId, recorded_at))
     INVALIDATE memory tree cache:
       - DELETE FROM memory_tree_cache WHERE connection_id = $connectionId
     QUEUE transcription job (if entry_type === 'voice' and transcription feature flag is on):
       - Add to Bull queue: 'transcription' with payload { entryId, mediaKey, connectionId }
     QUEUE notification job:
       - Add to Bull queue: 'notification' with payload
         { type: 'new_entry', connectionId, authorId: userId, entryId }
     LOG audit: { action: 'entry.created', resource_id: entryId }
     RETURN created entry (without media_url — client fetches that separately)

   async listEntries(userId: string, connectionId: string, dto: ListEntriesDto): Promise<PageResult<DiaryEntry>>
     BASE QUERY:
       SELECT * FROM diary_entries
       WHERE connection_id = $connectionId AND deleted_at IS NULL
     FILTER:
       - 'voice': AND entry_type = 'voice'
       - 'video': AND entry_type = 'video'
       - 'starred': AND is_starred = true
     CURSOR PAGINATION (recorded_at DESC, id DESC):
       - If cursor: decode it → AND (recorded_at, id) < ($t, $i)
     ORDER BY recorded_at DESC, id DESC
     LIMIT $limit + 1
     If result.length > limit: set next_cursor = encodeCursor(last item)
     DO NOT generate signed URLs here (expensive for 20 items) — client calls getEntry separately

   async getEntry(userId: string, connectionId: string, entryId: string): Promise<EntryWithUrl>
     - Find entry WHERE id=$entryId AND connection_id=$connectionId AND deleted_at IS NULL
     - If not found: throw NotFoundException('ENTRY_NOT_FOUND')
     - Generate signed media URL (1 hour expiry) via StorageService
     - Generate signed thumbnail URL if entry_type === 'video' and thumbnail_key exists
     - Return entry + media_url + thumbnail_url

   async starEntry(userId: string, connectionId: string, entryId: string, isStarred: boolean): Promise<DiaryEntry>
     - Update is_starred, starred_at (set to now() if starring, null if unstarring)

   async softDeleteEntry(userId: string, connectionId: string, entryId: string): Promise<void>
     OWNERSHIP: verify entry.author_id === userId (only author can delete)
     - Set deleted_at = now()
     - DO NOT delete media from R2 — a cleanup worker handles that after 90 days
     - LOG audit: { action: 'entry.deleted', resource_id: entryId }
     - If entry was the latest in connection: update diary_connections.last_entry_at
       to the new latest (sub-query)

   async recordPlay(userId: string, connectionId: string, entryId: string): Promise<number>
     - Increment play_count WHERE id=$entryId AND connection_id=$connectionId
     - This marks the entry as "listened" — used for unread_count calculation
     - RETURN updated play_count

5. CREATE src/entries/entries.controller.ts:
   POST   /connections/:id/entries/upload-url → getUploadUrl (JWT + ConnectionMemberGuard)
   POST   /connections/:id/entries            → createEntry  (JWT + ConnectionMemberGuard)
   GET    /connections/:id/entries            → listEntries  (JWT + ConnectionMemberGuard)
   GET    /connections/:id/entries/:entryId   → getEntry     (JWT + ConnectionMemberGuard)
   PATCH  /connections/:id/entries/:entryId/star  → starEntry  (JWT + ConnectionMemberGuard)
   DELETE /connections/:id/entries/:entryId   → softDeleteEntry (JWT + ConnectionMemberGuard)
   PATCH  /connections/:id/entries/:entryId/played → recordPlay (JWT + ConnectionMemberGuard)

6. IMPORTANT: In listEntries, do NOT include signed media URLs in the list response.
   The list returns metadata only. Signed URLs are expensive to generate and the client
   only plays one entry at a time — let them call getEntry when ready to play.
```

---

## PROMPT 08 — Flicker Module (Presence Signal + SSE Real-Time)

```
Implement the Flicker feature — the 3-second hold gesture that sends a
presence signal. Includes mutual reveal logic and SSE for real-time delivery.

REFERENCE: BACKEND_ARCHITECTURE.md Section 4 (Flicker APIs) and Section 7 (Real-time Architecture).

1. CREATE src/flicker/events.service.ts — SSE stream manager:

   Use RxJS Subject to maintain per-user streams.
   
   Private map: subjects = new Map<string, Subject<MessageEvent>>()
   
   getStream(userId: string, connectionId: string): Observable<MessageEvent>
     - key = `${userId}:${connectionId}`
     - Create Subject if not exists
     - Merge with heartbeat: interval(25000) → { data: { type: 'heartbeat' } }
     - On subscriber unsubscribe: clean up Subject from map if no subscribers
   
   push(userId: string, connectionId: string, event: SaanjhEvent): void
     - key = `${userId}:${connectionId}`
     - If Subject exists: .next({ data: event })
   
   broadcastToConnection(connectionId: string, event: SaanjhEvent): void
     - Get both user IDs from the connection
     - Call push() for each user in the connection

   Type SaanjhEvent = one of:
     { type: 'flicker_received'; flicker_id: string; sender_name: string; sent_at: string }
     { type: 'mutual_reveal'; mutual_at: string }
     { type: 'new_entry'; entry_id: string; author_id: string }
     { type: 'transcription_ready'; entry_id: string }
     { type: 'heartbeat' }

2. CREATE src/flicker/flicker.service.ts:

   async sendFlicker(senderId: string, connectionId: string): Promise<FlickerResult>
     RATE LIMIT: max 10 flickers per connection per hour
       key = 'flicker:${connectionId}:${senderId}:${hour}'
     
     FIND receiver:
       - Get connection, determine receiverId (the other user)
     
     INSERT flicker_event:
       { connection_id, sender_id: senderId, receiver_id: receiverId, sent_at: now() }
     
     CHECK MUTUAL REVEAL:
       SELECT id FROM flicker_events
       WHERE sender_id = $receiverId
         AND receiver_id = $senderId
         AND sent_at >= now() - INTERVAL '300 seconds'
         AND is_mutual = false
         AND connection_id = $connectionId
       LIMIT 1
     
     IF mutual found:
       - UPDATE both flicker rows: is_mutual = true, mutual_at = now()
       - Push SSE to BOTH users: { type: 'mutual_reveal', mutual_at }
       - Queue FCM notification to BOTH users (type: 'mutual_flicker')
     
     IF NOT mutual:
       - Push SSE to receiver (if online): { type: 'flicker_received', ... }
       - Queue FCM notification to receiver: type 'flicker_received'
     
     RETURN:
       { flicker_id, is_mutual, mutual_at, window_closes_at: sent_at + 5min }

   async getFlickerStatus(userId: string, connectionId: string): Promise<FlickerStatus>
     CACHE: 30-second TTL (use a simple in-memory cache for MVP)
     - Get latest flicker sent by userId to connection
     - Get latest flicker received by userId from connection  
     - Compute is_mutual and window_closes_at
     RETURN:
       { my_last_flicker_at, partner_last_flicker_at, is_mutual, window_closes_at }

   async getFlickerHistory(userId: string, connectionId: string, limit: number, cursor?: string): Promise<PageResult>
     SELECT * FROM flicker_events
     WHERE connection_id = $connectionId
     AND (sender_id = $userId OR receiver_id = $userId)
     ORDER BY sent_at DESC
     LIMIT $limit

3. CREATE src/flicker/flicker.controller.ts:

   @Sse(':id/events')
   @UseGuards(JwtAuthGuard, ConnectionMemberGuard)
   liveEvents(@Param('id') connectionId: string, @CurrentUser() user: User): Observable<MessageEvent>
     - Return eventsService.getStream(user.id, connectionId)
     - This keeps an SSE connection open — client receives real-time events

   @Post(':id')  (under /connections/:id/flicker)
   @UseGuards(JwtAuthGuard, ConnectionMemberGuard)
   sendFlicker(...): Promise<FlickerResult>

   @Get(':id/latest')
   getFlickerStatus(...)

   @Get(':id/history')
   getFlickerHistory(...)

   NOTE ON ROUTING: The SSE and flicker endpoints are nested under /connections/:id/
   Controller path: @Controller('connections')
   Flicker sub-routes: @Post(':id/flicker'), @Get(':id/flicker/latest'),
     @Get(':id/flicker/history'), @Sse(':id/events')

4. SSE KEEPALIVE:
   - The 25-second heartbeat in events.service.ts prevents proxy timeouts
   - Flutter client uses EventSource or http SSE package
   - On reconnect (SSE auto-reconnects): client re-subscribes, server re-creates stream

5. WHEN REDIS IS ADDED (at 2,000+ users):
   Add a TODO comment in events.service.ts:
   // TODO: When running multiple API instances, replace the in-memory Subject map
   // with Redis pub/sub. Each instance subscribes to 'saanjh:user:{userId}' channel
   // and publishes events there. Any instance can broadcast to any user.
```

---

## PROMPT 09 — Background Workers (Transcription + Cleanup)

```
Implement Bull queue workers for async processing.
The transcription worker is the most important — it runs after every voice upload.

REFERENCE: BACKEND_ARCHITECTURE.md Section 8 (Voice Transcription) and Section 10 (MVP Roadmap).

1. SETUP BULL in AppModule:
   BullModule.forRootAsync({
     useFactory: (config: ConfigService) => ({
       redis: { url: config.get('REDIS_URL') ?? undefined }
       // If no Redis URL: use in-memory mode (fine for MVP/single server)
     })
   })
   BullModule.registerQueue(
     { name: 'transcription' },
     { name: 'notification' },
     { name: 'pdf' },
     { name: 'cleanup' }
   )

2. CREATE src/workers/transcription.worker.ts:

   @Processor('transcription')
   export class TranscriptionWorker {
     constructor(
       private storageService: StorageService,
       private entriesRepo: Repository<DiaryEntry>,
       private eventsService: EventsService
     ) {}

     @Process('transcribe_voice')
     async handle(job: Job<{ entryId: string; mediaKey: string; connectionId: string }>): Promise<void>
       
       STEP 1: Update status to 'processing'
         UPDATE diary_entries SET transcription_status='processing' WHERE id=$entryId

       STEP 2: Download audio from R2
         const audioBuffer = await this.storageService.getObjectBuffer(mediaKey)
         If fails: update status='failed', return

       STEP 3: Call OpenAI Whisper API
         const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY })
         const file = new File([audioBuffer], 'audio.m4a', { type: 'audio/m4a' })
         const result = await openai.audio.transcriptions.create({
           file,
           model: 'whisper-1',
           language: 'hi',        // attempt Hindi first (auto-detects if wrong)
           response_format: 'text'
         })
         Timeout: 15 seconds (wrap in Promise.race with timeout)

       STEP 4: Update database
         UPDATE diary_entries
         SET transcription = $text, transcription_status = 'done'
         WHERE id = $entryId

       STEP 5: Notify connected users via SSE
         await eventsService.broadcastToConnection(connectionId, {
           type: 'transcription_ready', entry_id: entryId
         })

     @OnQueueFailed()
     async onFailed(job: Job, error: Error): Promise<void>
       - If job.attemptsMade >= 3: set transcription_status='failed'
       - Log to Sentry / console.error

   Configure job options: { attempts: 3, backoff: { type: 'exponential', delay: 5000 } }

3. CREATE src/workers/cleanup.worker.ts:

   @Processor('cleanup')
   export class CleanupWorker {

     @Process('delete_media')
     async deleteMedia(job: Job<{ mediaKey: string; thumbnailKey?: string }>): Promise<void>
       - storageService.deleteObject(mediaKey)
       - If thumbnailKey: storageService.deleteObject(thumbnailKey)
     
     @Process('delete_user_data')
     async deleteUserData(job: Job<{ userId: string }>): Promise<void>
       - This runs 30 days after account deletion request
       - Hard delete: users row (with deleted_at set 30+ days ago)
       - Hard delete: personal_journal_entries
       - Hard delete: device_sessions, otp_verifications
       - Queue media deletion for all personal journal media keys
       - Log: audit_logs { action: 'account.hard_deleted' }
       NOTE: Shared diary entries are NOT deleted — partner still owns them.
             Set author_id references to NULL or a 'deleted_user' sentinel.
   
4. CREATE a NestJS @Cron scheduled task in a new file:
   src/workers/scheduled-tasks.service.ts

   @Injectable()
   export class ScheduledTasksService {

     @Cron('0 0 * * *')  // midnight IST
     async cleanupExpiredOtps(): Promise<void>
       DELETE FROM otp_verifications WHERE expires_at < now() - INTERVAL '1 hour'

     @Cron('0 0 * * *')  // midnight IST
     async cleanupExpiredInvites(): Promise<void>
       UPDATE invites SET status='expired'
       WHERE status='pending' AND expires_at < now()

     @Cron('0 2 * * *')  // 2 AM IST — run during low traffic
     async cleanupOrphanedMedia(): Promise<void>
       - Find diary_entries WHERE deleted_at < now() - INTERVAL '90 days'
         AND media_key IS NOT NULL
       - For each: queue cleanup job { type: 'delete_media', mediaKey, thumbnailKey }
       - Set media_key = NULL after queuing (prevent double-deletion)

     @Cron('0 2 * * *')  // 2 AM IST
     async hardDeleteScheduledAccounts(): Promise<void>
       - Find users WHERE deleted_at < now() - INTERVAL '30 days'
       - For each: queue cleanup job { type: 'delete_user_data', userId }

5. Register all workers and ScheduledTasksService in AppModule.

6. For MVP with NO Redis:
   - Bull can run without Redis using an in-memory queue
   - Set a comment: if REDIS_URL not set → jobs run in-process (fine for MVP)
   - Add TODO: configure REDIS_URL on Railway when user base grows past 500
```

---

## PROMPT 10 — Memory Tree Module

```
Implement the Memory Tree — the living seasonal visualization of diary health.
This is the most data-intensive query in Saanjh.

REFERENCE: BACKEND_ARCHITECTURE.md Section 4 (Memory Tree APIs) and Section 3 (memory_tree_cache schema).

1. CREATE src/memory-tree/memory-tree.service.ts:

   CORE DATA STRUCTURE:
   interface MonthData {
     year_month: string;       // '2026-05'
     entry_count: number;
     voice_count: number;
     video_count: number;
     mood_distribution: Record<string, number>;
     has_milestone: boolean;
     node_health: number;      // 0.0 to 1.0
   }
   interface MemoryTreeData {
     months: MonthData[];
     tree_health: number;
     diary_weather: string;
     streak_count: number;
     longest_streak: number;
     total_entries: number;
     active_months: number;
   }

   async getMemoryTree(userId: string, connectionId: string): Promise<MemoryTreeData>
     STEP 1: Check cache
       SELECT * FROM memory_tree_cache WHERE connection_id = $connectionId
       If cache exists AND last_computed_at > now() - INTERVAL '10 minutes':
         Return cached data (parse monthly_data JSONB + pull streak from diary_connections)
     
     STEP 2: Compute fresh if cache miss/stale
       Call computeMemoryTree(connectionId)
       Update cache
       Return computed data

   async computeMemoryTree(connectionId: string): Promise<MemoryTreeData>
     MONTHLY AGGREGATION QUERY:
       SELECT
         TO_CHAR(DATE_TRUNC('month', recorded_at AT TIME ZONE 'Asia/Kolkata'), 'YYYY-MM') AS year_month,
         COUNT(*) AS entry_count,
         COUNT(*) FILTER (WHERE entry_type='voice') AS voice_count,
         COUNT(*) FILTER (WHERE entry_type='video') AS video_count,
         COUNT(*) FILTER (WHERE mood='happy') AS mood_happy,
         COUNT(*) FILTER (WHERE mood='calm') AS mood_calm,
         COUNT(*) FILTER (WHERE mood='thoughtful') AS mood_thoughtful,
         COUNT(*) FILTER (WHERE mood='missing') AS mood_missing,
         COUNT(*) FILTER (WHERE mood='excited') AS mood_excited
       FROM diary_entries
       WHERE connection_id = $connectionId AND deleted_at IS NULL
       GROUP BY year_month
       ORDER BY year_month ASC
     
     COMPUTE node_health per month:
       Node health = min(1.0, entry_count / 10.0)
       (10 entries in a month = full health; scales linearly)
     
     COMPUTE tree_health (overall):
       Average of last 3 months' node_health values
       (Recency-weighted: current month weight 0.5, prev 0.3, prev-prev 0.2)
     
     CHECK milestones: query streak_milestones for this connection
     
     FETCH streak from diary_connections (streak_count, longest_streak)
     
     UPSERT cache:
       INSERT INTO memory_tree_cache (connection_id, monthly_data, total_entries,
         active_months, tree_health, last_computed_at)
       VALUES ($1, $2, $3, $4, $5, now())
       ON CONFLICT (connection_id) DO UPDATE SET ...

   async getMonthDetail(userId: string, connectionId: string, yearMonth: string, filter: string): Promise<MonthDetailResult>
     - Parse yearMonth: '2026-05' → startDate, endDate
     - Query diary_entries with optional filter (voice/video/starred)
     - Return entries for that month + month stats
     NOTE: This does NOT use the cache — live query for fresh data

   async invalidateCache(connectionId: string): Promise<void>
     - DELETE FROM memory_tree_cache WHERE connection_id = $connectionId
     - Called after every diary entry create/delete

2. DIARY WEATHER CALCULATION (call this when streak changes):
   computeDiaryWeather(streakCount: number, daysSinceLastEntry: number): string
     if daysSinceLastEntry > 30: return 'dormant'
     if streakCount >= 30 and daysSinceLastEntry <= 2: return 'sunny'
     if streakCount >= 14 and daysSinceLastEntry <= 3: return 'partly_cloudy'
     if streakCount >= 3 and daysSinceLastEntry <= 5: return 'cloudy'
     return 'dormant'

3. CREATE src/memory-tree/memory-tree.controller.ts:
   GET /connections/:id/memory-tree            → getMemoryTree (JWT + ConnectionMemberGuard)
   GET /connections/:id/memory-tree/:yearMonth → getMonthDetail (JWT + ConnectionMemberGuard)
   Cache hint: set Cache-Control: max-age=600 on getMemoryTree response

4. QUEUE-BASED CACHE RECOMPUTATION:
   When an entry is created, instead of immediately recomputing (expensive),
   just invalidate the cache. The next read will recompute fresh.
   For high-traffic connections (many reads): add a Bull job to recompute
   in the background so the next read hits the cache.
```

---

## PROMPT 11 — On This Day Module

```
Implement "On This Day" — entries from the same calendar date in past years.
This is a high-retention feature that surfaces emotional memories.

REFERENCE: BACKEND_ARCHITECTURE.md Section 4 (On This Day APIs).

1. CREATE src/on-this-day/on-this-day.service.ts:

   async getOnThisDay(userId: string, connectionId: string, date?: string): Promise<OnThisDayResult>
     PARSE DATE:
       - If date provided: parse as 'YYYY-MM-DD' (validate format)
       - If not provided: use today in Asia/Kolkata timezone
         const istNow = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Kolkata' }))
         month = istNow.getMonth() + 1, day = istNow.getDate()
     
     QUERY — uses idx_entries_anniversary index:
       SELECT * FROM diary_entries
       WHERE connection_id = $connectionId
         AND deleted_at IS NULL
         AND EXTRACT(MONTH FROM recorded_at AT TIME ZONE 'Asia/Kolkata') = $month
         AND EXTRACT(DAY FROM recorded_at AT TIME ZONE 'Asia/Kolkata') = $day
         AND DATE_TRUNC('year', recorded_at) < DATE_TRUNC('year', now())
       ORDER BY recorded_at DESC
     
     EXTRACT unique years:
       years = [...new Set(entries.map(e => e.recorded_at.getFullYear()))]
     
     RETURN:
       { entries: DiaryEntry[], years: number[], has_entries: boolean }

2. CREATE src/on-this-day/on-this-day.controller.ts:
   GET /connections/:id/on-this-day → getOnThisDay (JWT + ConnectionMemberGuard)
   
   Set cache hint: Cache-Control: max-age=3600 (entries from past years don't change)

3. IMPORTANT TIMEZONE NOTE:
   All date comparisons must use Asia/Kolkata timezone (IST = UTC+5:30).
   A recording made at 11 PM IST must appear on the correct IST date,
   not UTC date. Always use AT TIME ZONE 'Asia/Kolkata' in SQL queries.
```

---

## PROMPT 12 — Memory Jar Module

```
Implement Memory Jar — starred entries surfaced on home screen open.
Uses a time-gate to prevent over-surfacing (max once per 4 hours per connection).

REFERENCE: BACKEND_ARCHITECTURE.md Section 4 (Memory Jar APIs).

1. CREATE src/memory-jar/memory-jar.service.ts:

   async surfaceMemory(userId: string, connectionId: string): Promise<SurfaceResult>
     TIME GATE CHECK:
       - Key: 'jar_gate:${userId}:${connectionId}'
       - Check rate_limit_counters: last surface was more than 4 hours ago
       - If within 4 hours: return { entry: null, total_starred: count, surfaced: false }
     
     FETCH RANDOM STARRED ENTRY:
       SELECT * FROM diary_entries
       WHERE connection_id = $connectionId
         AND is_starred = true
         AND deleted_at IS NULL
       ORDER BY RANDOM()
       LIMIT 1
     
     If no starred entries: return { entry: null, total_starred: 0, surfaced: false }
     
     UPDATE time gate: upsert rate_limit_counters with current timestamp
     
     RETURN: { entry: DiaryEntry, total_starred, surfaced: true }
     
     NOTE on ORDER BY RANDOM(): fine for MVP at low scale. At 100k entries
     switch to: ORDER BY starred_at DESC OFFSET FLOOR(RANDOM() * count) LIMIT 1

   async getAllStarred(userId: string, connectionId: string, limit: number, cursor?: string): Promise<PageResult>
     SELECT * FROM diary_entries
     WHERE connection_id = $connectionId AND is_starred = true AND deleted_at IS NULL
     ORDER BY starred_at DESC
     CURSOR: (starred_at, id) pagination

2. CREATE src/memory-jar/memory-jar.controller.ts:
   GET /connections/:id/memory-jar/surface → surfaceMemory (JWT + ConnectionMemberGuard)
   GET /connections/:id/memory-jar         → getAllStarred  (JWT + ConnectionMemberGuard)
```

---

## PROMPT 13 — Streak & Milestones Module

```
Implement streak tracking and milestone detection.
The streak logic must be timezone-aware (IST) and handle the boundary case
where both users contribute to the same connection's streak.

REFERENCE: BACKEND_ARCHITECTURE.md Appendix (Streak Update Logic) and Section 4 (Streak APIs).

1. CREATE src/streaks/streaks.service.ts:

   MILESTONE_DAYS = [7, 30, 60, 100, 200, 365]

   async onNewEntry(connectionId: string, recordedAt: Date): Promise<void>
     This is called by entries.service.ts after every successful entry creation.
     
     CONVERT to IST date:
       const istDate = toISTDate(recordedAt)
       // Use: format(utcToZonedTime(recordedAt, 'Asia/Kolkata'), 'yyyy-MM-dd')
     
     FETCH connection:
       SELECT streak_count, longest_streak, streak_last_date, streak_started_at
       FROM diary_connections WHERE id = $connectionId
       (Use a SELECT ... FOR UPDATE to prevent race conditions)
     
     STREAK LOGIC:
       if (!streak_last_date):
         // First entry ever
         streak_count = 1, streak_last_date = istDate,
         streak_started_at = istDate, longest_streak = 1
       else:
         daysSinceLast = differenceInCalendarDays(istDate, streak_last_date)
         if daysSinceLast === 0:
           return (already recorded today — no change)
         else if daysSinceLast === 1:
           // Consecutive day
           newStreak = streak_count + 1
           longest_streak = max(newStreak, longest_streak)
           streak_count = newStreak
           streak_last_date = istDate
           diary_weather = computeWeather(newStreak, 1)
         else:
           // Streak broken
           streak_count = 1, streak_last_date = istDate,
           streak_started_at = istDate
           diary_weather = 'partly_cloudy'
     
     UPDATE diary_connections with new values
     
     CHECK AND FIRE MILESTONES (only on streak increase):
       await this.checkMilestones(connectionId, streak_count, connection)

   async checkMilestones(connectionId: string, streakCount: number, connection: DiaryConnection): Promise<void>
     if (!MILESTONE_DAYS.includes(streakCount)) return
     
     CHECK if already achieved:
       SELECT 1 FROM streak_milestones
       WHERE connection_id = $connectionId AND milestone_days = $streakCount
     
     If not exists:
       INSERT INTO streak_milestones (connection_id, milestone_days)
       
       Queue notification for BOTH users:
         notificationsQueue.add('push', {
           userIds: [connection.user_a_id, connection.user_b_id],
           type: 'milestone',
           data: { connection_id: connectionId, days: streakCount }
         })

   computeWeather(streakCount: number, daysSinceLast: number): string
     if daysSinceLast > 30: return 'dormant'
     if streakCount >= 30 && daysSinceLast <= 2: return 'sunny'
     if streakCount >= 14 && daysSinceLast <= 3: return 'partly_cloudy'
     if streakCount >= 3 && daysSinceLast <= 5: return 'cloudy'
     return 'dormant'

   async getStreakData(userId: string, connectionId: string): Promise<StreakData>
     - Fetch from diary_connections
     - Compute at_risk: streak_count > 0 AND streak_last_date < today in IST
     - Fetch milestones from streak_milestones WHERE connection_id = $connectionId
     - Mark seen_by_me based on whether userId is user_a or user_b
     RETURN: { current_streak, longest_streak, streak_started_at, days_since_last_entry,
               at_risk, total_entry_days, milestones }

   async markMilestoneSeen(userId: string, connectionId: string, days: number): Promise<void>
     - Determine if user is user_a or user_b in this connection
     - UPDATE streak_milestones SET seen_by_a = true WHERE connection_id=$id AND milestone_days=$days
       (or seen_by_b if user is user_b)

2. CREATE src/streaks/streaks.controller.ts:
   GET  /connections/:id/streak                       → getStreakData (JWT + ConnectionMemberGuard)
   POST /connections/:id/milestones/:days/seen        → markMilestoneSeen (JWT + ConnectionMemberGuard)
```

---

## PROMPT 14 — Personal Journal Module

```
Implement the Personal Journal — completely private, never shared with partner.
This is a separate, isolated feature with its own storage namespace.

REFERENCE: BACKEND_ARCHITECTURE.md Section 4 (Personal Journal APIs).

SECURITY INVARIANT: Every query in this module MUST include user_id = $currentUserId.
No connection-based access. No admin visibility into content.

1. CREATE src/journal/dto/create-journal-entry.dto.ts:
   class CreateJournalEntryDto {
     @IsIn(['voice','video','text']) entry_type: string;
     @IsOptional() @IsString() media_key?: string;
     @IsOptional() @IsString() @MaxLength(5000) text_content?: string;
     @IsOptional() @IsInt() @Min(1) @Max(300) duration_seconds?: number;
     @IsOptional() @IsIn(['happy','calm','thoughtful','missing','excited']) mood?: string;
   }

2. CREATE src/journal/journal.service.ts:

   async getUploadUrl(userId: string, dto: JournalUploadUrlDto): Promise<UploadUrlResult>
     - No 20-second duration limit for personal journal (unlike shared diary)
     - Key: StorageService.journalKey(userId, randomUUID())
     - Return { upload_url, media_key, expires_in: 900 }

   async createEntry(userId: string, dto: CreateJournalEntryDto): Promise<PersonalJournalEntry>
     - If media_key provided: verify exists in R2
     - Verify media_key starts with `entries/journal/${userId}/` (security check)
     - INSERT personal_journal_entries
     - Return created entry

   async listEntries(userId: string, limit: number, cursor?: string, filter?: string): Promise<PageResult>
     SELECT * FROM personal_journal_entries
     WHERE user_id = $userId AND deleted_at IS NULL
     Filter by entry_type if filter is 'voice'/'video'/'text'
     Filter by is_starred if filter is 'starred'
     ORDER BY recorded_at DESC
     CURSOR pagination

   async getEntry(userId: string, entryId: string): Promise<EntryWithUrl>
     SELECT * FROM personal_journal_entries
     WHERE id = $entryId AND user_id = $userId AND deleted_at IS NULL
     -- user_id check is MANDATORY — cannot skip
     Generate signed URL if media_key exists

   async starEntry(userId: string, entryId: string, isStarred: boolean): Promise<PersonalJournalEntry>
     UPDATE WHERE id=$entryId AND user_id=$userId

   async deleteEntry(userId: string, entryId: string): Promise<void>
     UPDATE SET deleted_at=now() WHERE id=$entryId AND user_id=$userId
     DO NOT hard delete — same policy as shared diary entries

3. CREATE src/journal/journal.controller.ts:
   POST   /journal/upload-url     → getUploadUrl  (JWT required)
   POST   /journal/entries        → createEntry   (JWT required)
   GET    /journal/entries        → listEntries   (JWT required)
   GET    /journal/entries/:id    → getEntry      (JWT required)
   PATCH  /journal/entries/:id/star → starEntry   (JWT required)
   DELETE /journal/entries/:id    → deleteEntry   (JWT required)

4. IMPORTANT: Do NOT apply ConnectionMemberGuard here.
   The user_id = $currentUserId check inside each service method IS the access control.
```

---

## PROMPT 15 — Notifications Module

```
Implement the full notification system: FCM push via OneSignal, in-app bell, scheduled reminders.

REFERENCE: BACKEND_ARCHITECTURE.md Section 6 (Notifications Architecture).

1. CREATE src/notifications/notifications.service.ts:

   ONESIGNAL PUSH HELPER:
   async sendPush(userIds: string[], title: string, body: string, data: object): Promise<void>
     - Fetch FCM tokens: SELECT fcm_token FROM device_sessions
       WHERE user_id = ANY($userIds) AND is_active = true AND fcm_token IS NOT NULL
     - Call OneSignal REST API:
       POST https://onesignal.com/api/v1/notifications
       Body: {
         app_id: ONESIGNAL_APP_ID,
         include_player_ids: [...fcmTokens],
         headings: { en: title },
         contents: { en: body },
         data: data
       }
     - On 400/404 (invalid token): mark device_session.is_active = false
     - Never throw — push failures are non-fatal (always insert in-app notification)

   async createNotification(userId: string, type: string, title: string, body: string, data: object): Promise<void>
     STEP 1: Insert in-app notification row (always)
     STEP 2: Check user's notification preferences
       - If preference for this type is false: skip push
       - Check quiet hours: if current IST time is between quiet_hours_start and quiet_hours_end: skip push
     STEP 3: sendPush (if allowed)
     STEP 4: Update push_status on the notification row

   NOTIFICATION TEMPLATES (using processTemplate helper):
   processTemplate(template: string, vars: Record<string, string>): string
     - Simple {{variable}} replacement
   
   Templates for each type:
   new_entry:       title: '{{partner_name}} left you a voice note'
                    body:  '{{duration}}s — tap to listen'
   flicker_received: title: '{{partner_name}} is thinking of you'
                    body:  'They sent you a Flicker'
   mutual_flicker:  title: 'You and {{partner_name}} flickered each other ♥'
                    body:  'A little moment, shared.'
   streak_reminder: title: 'Your streak is at risk'
                    body:  "{{streak_count}} days with {{partner_name}} — don't break it"
   milestone:       title: '{{streak_count}} days together'
                    body:  'You and {{partner_name}} hit a milestone'
   occasion:        title: '{{occasion_name}} is in {{days_away}} days'
                    body:  'Record something special for {{partner_name}}'

2. CREATE src/notifications/notification-cron.service.ts:

   @Cron('0 14 * * *', { timeZone: 'Asia/Kolkata' })  // 8 PM IST (20:00 - 6h offset)
   async sendStreakReminders(): Promise<void>
     QUERY: Find connections at risk of streak breaking today
       SELECT dc.id, dc.user_a_id, dc.user_b_id, dc.streak_count
       FROM diary_connections dc
       WHERE dc.status = 'active'
         AND dc.streak_count > 0
         AND (dc.streak_last_date IS NULL OR dc.streak_last_date < CURRENT_DATE AT TIME ZONE 'Asia/Kolkata')
         AND NOT EXISTS (
           SELECT 1 FROM diary_entries de
           WHERE de.connection_id = dc.id
             AND DATE(de.recorded_at AT TIME ZONE 'Asia/Kolkata') = CURRENT_DATE AT TIME ZONE 'Asia/Kolkata'
             AND de.deleted_at IS NULL
         )
     For each at-risk connection: queue notification for both users

   @Cron('0 1 * * *', { timeZone: 'Asia/Kolkata' })   // 7 AM IST
   async sendOccasionReminders(): Promise<void>
     QUERY: Find occasions coming up based on remind_days_before
       SELECT o.*, dc.user_a_id, dc.user_b_id
       FROM occasions o
       JOIN diary_connections dc ON o.connection_id = dc.id
       WHERE (EXTRACT(MONTH FROM o.occasion_date) = EXTRACT(MONTH FROM CURRENT_DATE + (o.remind_days_before || ' days')::INTERVAL))
         AND (EXTRACT(DAY FROM o.occasion_date) = EXTRACT(DAY FROM CURRENT_DATE + (o.remind_days_before || ' days')::INTERVAL))
         AND (o.last_reminded_year IS NULL OR o.last_reminded_year < EXTRACT(YEAR FROM CURRENT_DATE))
     For each: send notification to both users, update last_reminded_year

3. CREATE the notification Bull worker (src/workers/notification.worker.ts):

   @Process('push')
   async handlePush(job: Job<{ type: string; connectionId?: string; userIds?: string[]; data: object }>): Promise<void>
     - Resolve userIds from connectionId if not directly provided
     - Call notificationsService.createNotification for each userId
     - Use appropriate template based on type
     - Handle failures gracefully — log but don't crash

4. CREATE src/notifications/notifications.controller.ts:
   GET  /notifications           → list in-app notifications (JWT required)
   POST /notifications/read      → mark as read (JWT required)
   GET  /notifications/preferences → get preferences (JWT required)
   PUT  /notifications/preferences → update preferences (JWT required)
   POST /notifications/device-token → register FCM token (JWT required)
   
   registerDeviceToken(userId: string, dto: DeviceTokenDto): Promise<void>
     Upsert device_sessions:
       ON CONFLICT (user_id, device_id) DO UPDATE SET
         fcm_token = $token, app_version = $version, last_used_at = now(), is_active = true
```

---

## PROMPT 16 — Occasions Module (AI Messages + Cron Reminders)

```
Implement occasion management — birthdays, anniversaries, Diwali — with
AI-powered message generation using the Claude API.

REFERENCE: BACKEND_ARCHITECTURE.md Section 4 (Occasion APIs).

1. CREATE src/occasions/dto/create-occasion.dto.ts:
   class CreateOccasionDto {
     @IsIn(['birthday','anniversary','diwali','eid','holi','raksha_bandhan','custom']) occasion_type: string;
     @IsOptional() @IsString() @MaxLength(100) occasion_name?: string;
     @IsDateString() occasion_date: string;
     @IsBoolean() is_recurring: boolean;
     @IsInt() @Min(1) @Max(30) remind_days_before: number;
   }

2. CREATE src/occasions/dto/generate-message.dto.ts:
   class GenerateMessageDto {
     @IsIn(['en','hi']) language: string;
     @IsOptional() @IsIn(['warm','playful','formal']) tone?: string;
   }

3. CREATE src/occasions/occasions.service.ts:

   async createOccasion(userId: string, connectionId: string, dto: CreateOccasionDto): Promise<Occasion>
     - Insert occasion row
     - If occasion_name not provided: use occasion_type as display name
     - Return created occasion

   async getOccasions(userId: string, connectionId: string): Promise<Occasion[]>
     SELECT * FROM occasions WHERE connection_id = $connectionId
     ORDER BY occasion_date ASC

   async deleteOccasion(userId: string, connectionId: string, occasionId: string): Promise<void>
     DELETE WHERE id = $occasionId AND connection_id = $connectionId AND created_by = $userId

   async generateAiMessage(userId: string, connectionId: string, occasionId: string, dto: GenerateMessageDto): Promise<string>
     RATE LIMIT: max 5 generations per occasion per day
     
     FETCH context:
       - occasion details
       - connection.relationship_type, name_for_a/b
       - requester's name (from users table)
     
     BUILD PROMPT:
       const prompt = `You are helping someone write a heartfelt voice note message for a special occasion.
       
       Context:
       - Occasion: ${occasion.occasion_name} (${occasion.occasion_type})
       - Relationship: ${relationship_type} (e.g., parent and child)
       - From: ${senderName}
       - Language: ${dto.language === 'hi' ? 'Hindi (use Devanagari script)' : 'English'}
       - Tone: ${dto.tone ?? 'warm'}
       
       Write a short, heartfelt message (2-3 sentences) that someone could read aloud as a voice note.
       Make it personal, emotional, and authentic. No generic phrases.
       Return only the message text, nothing else.`
     
     CALL CLAUDE API:
       Use @anthropic-ai/sdk
       const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY })
       const msg = await anthropic.messages.create({
         model: 'claude-haiku-4-5-20251001',
         max_tokens: 200,
         messages: [{ role: 'user', content: prompt }]
       })
     
     STORE result in occasion_ai_messages table
     RETURN generated text

4. Add ANTHROPIC_API_KEY to .env.example

5. CREATE src/occasions/occasions.controller.ts:
   GET    /connections/:id/occasions                         → getOccasions (JWT + ConnectionMemberGuard)
   POST   /connections/:id/occasions                         → createOccasion (JWT + ConnectionMemberGuard)
   DELETE /connections/:id/occasions/:occasionId             → deleteOccasion (JWT + ConnectionMemberGuard)
   POST   /connections/:id/occasions/:occasionId/generate    → generateAiMessage (JWT + ConnectionMemberGuard)
```

---

## PROMPT 17 — Memory Book Module (Orders + Razorpay + PDF)

```
Implement Memory Book physical print ordering with Razorpay payment and PDF generation.
₹399 self / ₹499 gift (feature-flagged — only shown when memory_book flag is enabled).

REFERENCE: BACKEND_ARCHITECTURE.md Section 4 (Memory Book APIs) and Section 8 (PDF Generation).

1. INSTALL: npm install razorpay pdfkit

2. CREATE src/memory-books/dto/preview-book.dto.ts:
   class PreviewBookDto {
     @IsUUID() connection_id: string;
     @IsDateString() date_from: string;
     @IsDateString() date_to: string;
   }

3. CREATE src/memory-books/dto/create-order.dto.ts:
   class CreateOrderDto {
     @IsUUID() connection_id: string;
     @IsIn(['self','gift']) order_type: string;
     @IsDateString() date_from: string;
     @IsDateString() date_to: string;
     @ValidateNested() @Type(() => ShippingAddressDto) shipping_address: ShippingAddressDto;
     @IsOptional() @ValidateNested() @Type(() => GiftRecipientDto) gift_recipient?: GiftRecipientDto;
   }

4. CREATE src/memory-books/memory-books.service.ts:

   PRICING:
   PRICE_SELF_PAISE = 39900    // ₹399
   PRICE_GIFT_PAISE = 49900    // ₹499

   async previewBook(userId: string, dto: PreviewBookDto): Promise<BookPreview>
     - Validate user is member of connection_id
     - COUNT entries in date range
     - Estimate pages: Math.ceil(entryCount * 1.2) + 5 (cover pages)
     - Fetch 3 recent entries as sample
     - RETURN: { entry_count, estimated_pages, price_paise, sample_entries }

   async createOrder(userId: string, dto: CreateOrderDto): Promise<RazorpayOrderResult>
     - Check feature flag 'memory_book' is enabled
     - Validate user is member of connection
     - Count entries in range (must be > 0)
     
     RAZORPAY ORDER:
       const razorpay = new Razorpay({ key_id: RZP_KEY_ID, key_secret: RZP_KEY_SECRET })
       const rzpOrder = await razorpay.orders.create({
         amount: price_paise,
         currency: 'INR',
         receipt: `saanjh_${orderId}`,
         notes: { connection_id: dto.connection_id, user_id: userId }
       })
     
     INSERT memory_book_orders row with payment_status='pending'
     
     RETURN:
       { order_id, razorpay_order_id, amount_paise, currency, razorpay_key: RZP_KEY_ID }

   async verifyPayment(userId: string, orderId: string, dto: VerifyPaymentDto): Promise<MemoryBookOrder>
     SIGNATURE VERIFICATION (critical — prevents fraud):
       const body = `${dto.razorpay_order_id}|${dto.razorpay_payment_id}`
       const expectedSignature = crypto.createHmac('sha256', RZP_KEY_SECRET)
                                       .update(body).digest('hex')
       If expectedSignature !== dto.razorpay_signature:
         throw UnauthorizedException('PAYMENT_SIGNATURE_INVALID')
     
     UPDATE order: payment_status='paid', paid_at=now(), razorpay_payment_id
     
     QUEUE PDF generation job:
       pdfQueue.add('generate_memory_book', { orderId })
     
     RETURN updated order

   async getOrders(userId: string): Promise<MemoryBookOrder[]>
     SELECT * FROM memory_book_orders WHERE ordered_by = $userId ORDER BY created_at DESC

   async getOrder(userId: string, orderId: string): Promise<MemoryBookOrder>
     SELECT WHERE id=$orderId AND ordered_by=$userId

5. CREATE src/workers/pdf.worker.ts:

   @Process('generate_memory_book')
   async generatePdf(job: Job<{ orderId: string }>): Promise<void>
     FETCH order and entries:
       const order = await ordersRepo.findOne(orderId)
       const entries = await entriesRepo.find({
         where: { connection_id: order.connection_id, deleted_at: null },
         where: date range from order.date_from to order.date_to,
         order: { recorded_at: 'ASC' }
       })
     
     GENERATE PDF using pdfkit:
       const doc = new PDFDocument({ size: 'A5', margin: 40 })
       
       // Cover page
       doc.fontSize(28).text('Saanjh', { align: 'center' })
       doc.fontSize(14).text(connectionName, { align: 'center' })
       doc.fontSize(10).text(`${format(order.date_from, 'MMM yyyy')} – ${format(order.date_to, 'MMM yyyy')}`)
       
       // One entry per page
       for (const entry of entries) {
         doc.addPage()
         doc.fontSize(9).fillColor('#888888')
            .text(format(entry.recorded_at, 'dd MMMM yyyy, EEEE'), { align: 'right' })
         doc.moveDown()
         if (entry.transcription) {
           doc.fontSize(14).fillColor('#1a1a1a')
              .text(`"${entry.transcription}"`, { align: 'center', oblique: true })
         }
         doc.moveDown(0.5)
         doc.fontSize(8).fillColor('#aaaaaa')
            .text(`${entry.duration_seconds}s voice note`, { align: 'center' })
       }
       
       // Back cover
       doc.addPage()
       doc.fontSize(11).text('Made with Saanjh', { align: 'center' })
     
     UPLOAD to R2:
       const pdfKey = StorageService.bookKey(orderId)
       const buffer = await streamToBuffer(doc)
       await storageService.putObject(pdfKey, buffer, 'application/pdf')
     
     UPDATE order: pdf_key = pdfKey, print_status = 'pdf_ready'
     
     NOTIFY admin (Slack webhook or email): "Memory Book PDF ready: order ${orderId}"

6. CREATE src/memory-books/memory-books.controller.ts:
   POST /memory-books/preview          → previewBook (JWT required)
   POST /memory-books/orders           → createOrder (JWT required)
   POST /memory-books/orders/:id/payment/verify → verifyPayment (JWT required)
   GET  /memory-books/orders           → getOrders (JWT required)
   GET  /memory-books/orders/:id       → getOrder (JWT required)
```

---

## PROMPT 18 — Search Module

```
Implement full-text search over diary entry transcriptions using PostgreSQL.

REFERENCE: BACKEND_ARCHITECTURE.md Section 4 (Search APIs).

1. CREATE src/search/search.service.ts:

   async searchEntries(userId: string, query: string, connectionId?: string, limit = 20): Promise<SearchResult[]>
     VALIDATE: query must be at least 3 characters
     
     SECURITY: If connectionId provided, verify user is a member.
       If not provided: search across ALL user's connections.
     
     CONNECTION FILTER:
       If connectionId: use that single connection
       Else: get all connection IDs for this user first, then search across them
     
     FULL-TEXT SEARCH QUERY:
       SELECT de.*,
         ts_headline('english', de.transcription,
           plainto_tsquery('english', $query),
           'StartSel=<<, StopSel=>>, MaxWords=20, MinWords=10'
         ) AS snippet
       FROM diary_entries de
       WHERE de.connection_id = ANY($connectionIds)
         AND de.deleted_at IS NULL
         AND de.transcription_status = 'done'
         AND to_tsvector('english', COALESCE(de.transcription, '')) @@ plainto_tsquery('english', $query)
       ORDER BY ts_rank(to_tsvector('english', de.transcription), plainto_tsquery('english', $query)) DESC
       LIMIT $limit
     
     RETURN entries with snippet (highlighted matching words) replacing full transcription

2. CREATE src/search/search.controller.ts:
   GET /search/entries?q=&connection_id=&limit= → searchEntries (JWT required)
   
   Notes:
   - Only entries with transcription_status='done' are searchable
   - Results include snippet with matched words highlighted using <<word>> markers
   - Flutter can render these with simple string replacement for highlighting
```

---

## PROMPT 19 — Admin Module

```
Implement the admin API — metrics, user management, feature flags.
Protected by a separate JWT secret so admin tokens can't be generated by users.

REFERENCE: BACKEND_ARCHITECTURE.md Section 4 (Admin APIs).

1. All admin routes are under /v1/admin/*
   Apply AdminGuard (verifies ADMIN_JWT_SECRET) to the entire controller.
   Never return diary entry content or transcription text in admin APIs.

2. CREATE src/admin/admin.service.ts:

   async getUserList(page: number, limit: number, search?: string): Promise<AdminUserList>
     SELECT id, phone (masked), name, is_onboarded, is_active, is_verified,
            last_active_at, created_at, deleted_at
     FROM users
     WHERE deleted_at IS NULL
     If search: AND (name ILIKE '%${search}%')
     ORDER BY created_at DESC
     OFFSET/LIMIT pagination

   async getUserDetail(userId: string): Promise<AdminUserDetail>
     - User profile (no phone_hash, no full phone)
     - Connection count
     - Entry count
     - Device sessions (device_type, app_version, last_used_at)
     - Recent audit logs for this user (last 20)

   async suspendUser(adminId: string, userId: string, reason: string): Promise<void>
     - Set users.is_active = false
     - Set all device_sessions.is_active = false (force logout)
     - Log audit: { action: 'admin.user_suspended', user_id: userId, metadata: { reason } }
     NOTE: Content is NOT deleted — suspension is reversible

   async getAnalyticsOverview(): Promise<AnalyticsOverview>
     QUERIES (run in parallel):
     DAU: COUNT DISTINCT user_id FROM audit_logs WHERE created_at > now() - 1 day
     WAU: COUNT DISTINCT user_id FROM audit_logs WHERE created_at > now() - 7 days
     MAU: COUNT DISTINCT user_id FROM audit_logs WHERE created_at > now() - 30 days
     New signups today: COUNT FROM users WHERE DATE(created_at) = today
     Active connections: COUNT FROM diary_connections WHERE status='active'
     Entries today: COUNT FROM diary_entries WHERE DATE(created_at) = today AND deleted_at IS NULL
     
     RETURN: { dau, wau, mau, new_signups_today, active_connections, entries_today }

   async getFeatureFlags(): Promise<FeatureFlag[]>
     SELECT * FROM feature_flags ORDER BY key

   async updateFeatureFlag(key: string, isEnabled: boolean, rolloutPercentage: number): Promise<FeatureFlag>
     UPDATE feature_flags SET is_enabled=$1, rollout_percentage=$2, updated_at=now()
     WHERE key=$3

   async getOrders(page: number, status?: string): Promise<AdminOrderList>
     SELECT o.*, u.name as ordered_by_name
     FROM memory_book_orders o
     JOIN users u ON o.ordered_by = u.id
     WHERE ($status IS NULL OR o.payment_status = $status OR o.print_status = $status)
     ORDER BY o.created_at DESC

   async updateOrderStatus(orderId: string, printStatus: string, trackingNumber?: string): Promise<void>
     UPDATE memory_book_orders SET print_status=$1, tracking_number=$2 WHERE id=$3

3. CREATE src/admin/admin.controller.ts:
   GET    /admin/users                    → getUserList
   GET    /admin/users/:id                → getUserDetail
   PATCH  /admin/users/:id/suspend        → suspendUser
   GET    /admin/analytics/overview       → getAnalyticsOverview
   GET    /admin/analytics/entries        → entry counts per day (last 30 days)
   GET    /admin/analytics/flickers       → flicker counts per day (last 30 days)
   GET    /admin/feature-flags            → getFeatureFlags
   PATCH  /admin/feature-flags/:key       → updateFeatureFlag
   GET    /admin/orders                   → getOrders
   PATCH  /admin/orders/:id               → updateOrderStatus
```

---

## PROMPT 20 — Health Check, Rate Limiting & Global Error Handling

```
Implement production-readiness: health endpoint, rate limiting, global error filter, request logging.

1. CREATE src/health/health.controller.ts:
   GET /health
   Returns:
     {
       status: 'ok',
       db: 'ok' | 'error',
       timestamp: ISO string,
       uptime: process.uptime(),
       version: process.env.npm_package_version
     }
   
   DB check: run 'SELECT 1' query, set db='error' if it fails (don't throw — return 200 always)
   This endpoint must NEVER require auth — used by Uptime Robot.

2. CREATE src/filters/http-exception.filter.ts:
   @Catch(HttpException)
   export class HttpExceptionFilter implements ExceptionFilter
   
   Always return:
   {
     error: {
       code: string,        // from exception response if available, else HTTP status name
       message: string,
       statusCode: number
     }
   }
   
   Apply globally in main.ts: app.useGlobalFilters(new HttpExceptionFilter())

3. CREATE src/filters/all-exceptions.filter.ts:
   @Catch()
   export class AllExceptionsFilter implements ExceptionFilter
   
   For unexpected errors (500):
     - Log to Sentry if SENTRY_DSN is set: Sentry.captureException(exception)
     - Return: { error: { code: 'INTERNAL_ERROR', message: 'Something went wrong', statusCode: 500 } }
     - NEVER expose stack traces in production responses

4. INSTALL: npm install @sentry/node
   Initialize Sentry in main.ts BEFORE app creation if SENTRY_DSN is set:
     Sentry.init({ dsn: process.env.SENTRY_DSN, environment: process.env.NODE_ENV })

5. RATE LIMITING using the rate_limit_counters table (DB-based for MVP):
   CREATE src/guards/rate-limit.guard.ts:
   
   Decorator: @RateLimit(maxRequests: number, windowSeconds: number, keyPrefix?: string)
   
   Guard logic:
     key = `${keyPrefix ?? route}:${userId ?? ip}`
     SELECT count, window_start FROM rate_limit_counters WHERE key = $key
     
     If found AND window_start > now() - windowSeconds:
       If count >= maxRequests: throw TooManyRequestsException with Retry-After header
       Else: UPDATE SET count = count + 1
     Else:
       UPSERT: count = 1, window_start = now()
   
   Apply to: POST /auth/otp/send, POST /connections/invite, POST /connections/:id/flicker,
             POST /connections/:id/occasions/:id/generate, POST /entries/upload-url

6. CREATE src/interceptors/logging.interceptor.ts:
   @Injectable() export class LoggingInterceptor implements NestInterceptor
   
   On each request:
     - Log: [timestamp] METHOD /path - userId? - latencyMs
     - On error: log error code and message
   
   DO NOT log: request bodies (may contain sensitive data), OTPs, tokens
   Apply globally.

7. VERIFY PRODUCTION READINESS CHECKLIST:
   Run each of these manually and confirm:
   - [ ] GET /v1/health returns { status: 'ok', db: 'ok' }
   - [ ] POST /v1/auth/otp/verify without token returns 401 with { error: { code: 'INVALID_TOKEN' } }
   - [ ] POST /v1/connections/:id/entries with wrong user returns 403 FORBIDDEN
   - [ ] POST /v1/auth/otp/send 4 times in 10 minutes returns 429 on 4th
   - [ ] Any 500 error returns { error: { code: 'INTERNAL_ERROR' } } not a stack trace
   - [ ] npm run build succeeds with zero TypeScript errors
   - [ ] npm run test passes all unit tests
```

---

## PROMPT 21 — Deployment: Railway + Supabase + Cloudflare R2

```
Deploy the Saanjh backend to production. This makes the app live.

REFERENCE: BACKEND_ARCHITECTURE.md Section 2 (Infrastructure & Deployment).

1. SUPABASE SETUP:
   a. Go to supabase.com, create a new project called 'saanjh-prod'
   b. Save the connection string: Settings → Database → Connection string (URI)
      Format: postgresql://postgres:[PASSWORD]@[HOST]:5432/postgres
   c. Run migrations against Supabase:
      DATABASE_URL=<supabase_url> npm run migration:run
   d. Verify all tables created: Supabase dashboard → Table Editor
   e. Enable Row Level Security on personal_journal_entries as extra protection

2. CLOUDFLARE R2 SETUP:
   a. Go to Cloudflare dashboard → R2 → Create bucket: 'saanjh-media'
   b. Enable versioning on the bucket (keeps deleted objects 90 days)
   c. Create R2 API token with read+write permissions
   d. Note: Account ID, Access Key ID, Secret Access Key, Bucket Name
   e. R2 endpoint format: https://{ACCOUNT_ID}.r2.cloudflarestorage.com

3. RAILWAY SETUP:
   a. Go to railway.app, connect GitHub repo
   b. New Project → Deploy from GitHub → select saanjh-backend repo
   c. Set all environment variables from .env.example:
      DATABASE_URL, JWT_PRIVATE_KEY (paste full PEM), JWT_PUBLIC_KEY,
      REFRESH_TOKEN_SECRET (generate: openssl rand -hex 64),
      PHONE_HASH_SALT (generate: openssl rand -hex 32),
      R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME, R2_ENDPOINT,
      OPENAI_API_KEY, ONESIGNAL_APP_ID, ONESIGNAL_API_KEY,
      ADMIN_JWT_SECRET (generate: openssl rand -hex 32),
      NODE_ENV=production
   d. Set start command: npm run migration:run && npm run start:prod
   e. Railway will auto-deploy on every push to main branch

4. GENERATE RS256 KEY PAIR:
   openssl genrsa -out private.pem 2048
   openssl rsa -in private.pem -pubout -out public.pem
   
   Set in Railway:
   JWT_PRIVATE_KEY = contents of private.pem (replace newlines with \n)
   JWT_PUBLIC_KEY  = contents of public.pem (replace newlines with \n)
   
   In jwt.strategy.ts and auth.service.ts, handle multiline PEM:
   const privateKey = process.env.JWT_PRIVATE_KEY.replace(/\\n/g, '\n')

5. ONESIGNAL SETUP:
   a. Create account at onesignal.com
   b. New App → 'Saanjh' → choose Google Android + Apple iOS
   c. Android: provide Firebase Cloud Messaging Server Key
      (Firebase console → Project Settings → Cloud Messaging → Server key)
   d. iOS: provide APNs certificate from Apple Developer Account
   e. Get App ID and REST API Key → set as ONESIGNAL_APP_ID and ONESIGNAL_API_KEY

6. UPTIME ROBOT SETUP:
   a. Create free account at uptimerobot.com
   b. New Monitor → HTTP(S) → URL: https://your-railway-domain.railway.app/v1/health
   c. Check interval: 5 minutes
   d. Alert contacts: your phone number + email

7. SENTRY SETUP:
   a. Create project at sentry.io → NestJS
   b. Get DSN → set as SENTRY_DSN in Railway env vars
   c. Test: trigger a 500 error on staging → confirm it appears in Sentry

8. VERIFY END-TO-END:
   Using a REST client (Postman or curl):
   a. POST /v1/auth/otp/send { "phone": "+91XXXXXXXXXX" }
      → Should return { message: "OTP sent" }
   b. POST /v1/auth/otp/verify { "phone": "...", "otp": "..." }
      → Should return { access_token, refresh_token, is_new_user: true }
   c. PUT /v1/onboarding/profile (with Bearer token)
      → Should return updated user profile
   d. GET /v1/health
      → Should return { status: 'ok', db: 'ok' }
   e. Check Railway logs — no error messages on startup

9. STAGING ENVIRONMENT:
   a. Create a second Railway environment: 'staging'
   b. Create a second Supabase project: 'saanjh-staging'
   c. Use the same R2 bucket but with key prefix 'staging/' in staging env
      (Add STORAGE_PREFIX=staging/ env var and use it in StorageService.voiceKey etc.)
   d. Railway auto-creates staging deploys from non-main branches (preview deployments)
```

---

## PROMPT 22 — Flutter Integration: Connecting the App to the Backend

```
Wire the Flutter app to the new NestJS backend. This prompt is for the Flutter side.

REFERENCE: All API endpoints defined in BACKEND_ARCHITECTURE.md Section 4.

1. ADD HTTP packages to Flutter pubspec.yaml:
   dio: ^5.x.x               # HTTP client with interceptors
   dio_cache_interceptor: ^3  # response caching
   flutter_secure_storage: ^9 # store refresh token
   app_links: ^6              # deep link handling for invites
   eventsource: ^1            # or use http package SSE support

2. CREATE lib/backend/api_client.dart:
   Base URL: https://your-railway-domain.railway.app/v1
   
   Dio interceptor for auth:
   - On every request: add Authorization: Bearer {accessToken} header
   - On 401 response: attempt token refresh using refresh_token from secure storage
   - If refresh succeeds: retry original request with new access_token
   - If refresh fails (401 again): clear tokens, redirect to login screen

3. CREATE lib/backend/auth_api.dart:
   sendOtp(String phone) → POST /auth/otp/send
   verifyOtp(String phone, String otp, DeviceInfo device) → POST /auth/otp/verify
   refreshToken(String refreshToken) → POST /auth/token/refresh
   logout(String deviceId) → POST /auth/logout

4. CREATE lib/backend/connections_api.dart:
   createInvite(CreateInviteRequest req) → POST /connections/invite
   getInviteDetails(String code) → GET /connections/invite/{code}
   acceptInvite(String code, String name) → POST /connections/invite/{code}/accept
   getConnections() → GET /connections
   getConnectionHealth(String id) → GET /connections/{id}/health

5. CREATE lib/backend/entries_api.dart:
   getUploadUrl(String connectionId, UploadUrlRequest req) → POST /connections/{id}/entries/upload-url
   createEntry(String connectionId, CreateEntryRequest req) → POST /connections/{id}/entries
   listEntries(String connectionId, {String? cursor, String? filter}) → GET /connections/{id}/entries
   getEntry(String connectionId, String entryId) → GET /connections/{id}/entries/{entryId}
   starEntry(String connectionId, String entryId, bool starred) → PATCH .../star
   deleteEntry(String connectionId, String entryId) → DELETE
   recordPlay(String connectionId, String entryId) → PATCH .../played

6. MEDIA UPLOAD FLOW in Flutter:
   Step 1: Call getUploadUrl() to get pre-signed URL
   Step 2: Upload directly to R2 using Dio PUT request to the pre-signed URL
            (NOT to the API — directly to R2)
   Step 3: Call createEntry() with the returned media_key
   
   Show upload progress using Dio's onSendProgress callback.

7. CREATE lib/backend/flicker_api.dart:
   sendFlicker(String connectionId) → POST /connections/{id}/flicker
   getFlickerStatus(String connectionId) → GET /connections/{id}/flicker/latest
   subscribeToEvents(String connectionId) → GET /connections/{id}/events (SSE)
   
   SSE subscription in Flutter:
   Stream<SaanjhEvent> subscribeToEvents(String connectionId) {
     final url = '$baseUrl/connections/$connectionId/events';
     // Use http package with streaming or eventsource package
     // Parse SSE data lines, emit typed SaanjhEvent objects
     // Auto-reconnect on disconnect (SSE spec handles this)
   }

8. UPDATE DiaryStore, FlickerStore, UserStore to call the real API instead of
   returning mock data. Keep the Listenable pattern — just replace mock data
   with API calls and call notifyListeners() after data arrives.

9. DEVICE INFO for session registration:
   Use device_info_plus package to get:
   - deviceId: unique device identifier
   - deviceType: 'android' or 'ios'
   - osVersion: Android API level or iOS version
   Pass these in POST /auth/otp/verify body and POST /notifications/device-token

10. FCM TOKEN REGISTRATION:
    After successful login AND after FCM token refresh:
    POST /notifications/device-token { fcm_token, device_id, device_type, app_version }
    
    Setup: add firebase_messaging package, get FCM token in main.dart,
    call registerDeviceToken API after auth succeeds.
```

---

## PROMPT 23 — Security Hardening & Production Final Checklist

```
Final security pass before going live. Run every item on this checklist.

REFERENCE: BACKEND_ARCHITECTURE.md Section 12 (Production Readiness Checklist) and Section 9 (Security).

1. VERIFY ALL SECURITY MEASURES ARE IN PLACE:

   AUTH SECURITY:
   - [ ] OTP stored as SHA-256 hash only (never plain text in DB)
   - [ ] Refresh token stored as SHA-256 hash only
   - [ ] Refresh token rotation: old token invalidated immediately on use
   - [ ] JWT uses RS256 (asymmetric) — private key only on server
   - [ ] Access token expiry: 15 minutes confirmed (decode a token, check exp claim)
   - [ ] OTP brute force: verify 5 wrong attempts → 30 min lockout works
   - [ ] OTP rate limit: verify 3 sends per 10 min per phone works
   - [ ] Account deletion: verify soft delete → 30 day grace → hard delete chain

   DATA PRIVACY:
   - [ ] ConnectionMemberGuard on every diary/entry/flicker endpoint
   - [ ] Personal journal queries: every query has AND user_id = $currentUser
   - [ ] Phone numbers masked in all API responses (show only last 4)
   - [ ] Transcription text never appears in admin APIs or logs
   - [ ] R2 media URLs: never public, always signed (1h expiry)
   - [ ] media_key path check in createEntry: verify key belongs to this connectionId
   
   API SECURITY:
   - [ ] CORS: only saanjh.app origin in production (not * wildcard)
   - [ ] Helmet.js: X-Content-Type-Options, X-Frame-Options, HSTS headers present
   - [ ] Input validation on every DTO (class-validator)
   - [ ] SQL injection impossible: no raw string concatenation in queries
   - [ ] Sentry DSN set and tested with a deliberate 500 error

   PAYMENT SECURITY:
   - [ ] Razorpay signature verification in verifyPayment (HMAC-SHA256)
   - [ ] Razorpay key_secret never returned to client
   - [ ] Payment amount set server-side only (never trust client amount)

2. LOAD TEST (basic):
   Install: npm install -g artillery
   
   Create artillery-test.yml:
     config:
       target: https://your-staging-url.railway.app
       phases:
         - duration: 60
           arrivalRate: 10
     scenarios:
       - flow:
           - get:
               url: '/v1/health'
   
   Run: artillery run artillery-test.yml
   Expected: P95 < 300ms, 0 errors at 10 req/sec
   
   Run a second test on /v1/connections (with valid JWT) to test the DB query path.

3. DATABASE INDEX VERIFICATION:
   Connect to Supabase SQL editor, run EXPLAIN ANALYZE on these queries:
   
   a. Diary thread: EXPLAIN ANALYZE SELECT * FROM diary_entries
      WHERE connection_id = 'test-uuid' AND deleted_at IS NULL
      ORDER BY recorded_at DESC LIMIT 20;
      Expected: Index Scan using idx_entries_thread
   
   b. On This Day: EXPLAIN ANALYZE SELECT * FROM diary_entries
      WHERE connection_id = 'test-uuid'
      AND EXTRACT(MONTH FROM recorded_at)::INT = 5
      AND EXTRACT(DAY FROM recorded_at)::INT = 20
      AND deleted_at IS NULL;
      Expected: Index Scan using idx_entries_anniversary
   
   c. Flicker status: EXPLAIN ANALYZE SELECT * FROM flicker_events
      WHERE sender_id = 'test-uuid' AND receiver_id = 'test-uuid2'
      ORDER BY sent_at DESC LIMIT 1;
      Expected: Index Scan using idx_flicker_window
   
   If any query shows Seq Scan: add the missing index before going live.

4. BACKUP VERIFICATION:
   a. Trigger a Supabase manual backup from dashboard
   b. Restore it to a temporary Supabase project
   c. Verify row counts match: SELECT COUNT(*) FROM users; etc.
   d. Delete the temporary project

5. ENVIRONMENT VARIABLE AUDIT:
   In Railway production environment, verify all these are set and non-empty:
   DATABASE_URL, JWT_PRIVATE_KEY, JWT_PUBLIC_KEY, REFRESH_TOKEN_SECRET,
   PHONE_HASH_SALT, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME,
   R2_ENDPOINT, ONESIGNAL_APP_ID, ONESIGNAL_API_KEY, SENTRY_DSN,
   ADMIN_JWT_SECRET, NODE_ENV=production, ALLOWED_ORIGINS=https://saanjh.app

6. GDPR/DPDP ACT CHECKLIST:
   - [ ] Privacy policy live at saanjh.app/privacy before any users sign up
   - [ ] Terms of service live at saanjh.app/terms
   - [ ] Explicit consent checkbox in Flutter onboarding (not pre-checked)
   - [ ] Data export endpoint tested: GET /v1/settings/data-export
   - [ ] Account deletion flow tested end-to-end (OTP → soft delete → can cancel)
   - [ ] audit_logs retention: add cleanup job to delete logs > 2 years old

7. FINAL SMOKE TEST (run in production, not staging):
   Using the actual Saanjh Flutter app on a real device:
   a. Install app on Android device
   b. Sign up with real phone number — verify OTP arrives via SMS
   c. Complete onboarding (set name)
   d. Create an invite → share via WhatsApp
   e. Install on second device, sign up with second number, accept invite
   f. Record a voice note from device 1 → verify device 2 gets push notification
   g. Send Flicker from device 1 → verify device 2 gets notification
   h. Both devices send Flicker → verify mutual reveal appears
   i. Star an entry → verify it appears in Memory Jar
   j. Check On This Day (may need test data from past dates)
   k. GET /v1/health from browser → confirms { status: 'ok', db: 'ok' }
   
   If all pass: the backend is production-ready.
```

---

## IMPLEMENTATION ORDER SUMMARY

| # | Prompt | What it builds | Dependency |
|---|--------|----------------|------------|
| 01 | Project Init | NestJS skeleton, folders, CI/CD | None |
| 02 | Database Entities | All 18 TypeORM entities + migrations | 01 |
| 03 | Shared Services | Storage (R2), middleware, guards, helpers | 02 |
| 04 | Auth Module | OTP, JWT, sessions, account deletion | 03 |
| 05 | Users Module | Profile, onboarding, feature flags | 04 |
| 06 | Connections Module | Invites, WhatsApp deep links, 1-to-1 pairs | 04, 05 |
| 07 | Entries Module | Upload, voice diary CRUD, soft delete | 03, 06 |
| 08 | Flicker Module | Presence signal, mutual reveal, SSE | 06, 07 |
| 09 | Workers | Transcription (Whisper), cleanup cron | 07, 08 |
| 10 | Memory Tree | Monthly aggregation, tree health, cache | 07, 09 |
| 11 | On This Day | Date-based memory surfacing | 07 |
| 12 | Memory Jar | Starred entry surfacing with time gate | 07 |
| 13 | Streaks | Streak tracking, milestones, diary weather | 07, 09 |
| 14 | Personal Journal | Private entries, fully isolated | 03 |
| 15 | Notifications | FCM/OneSignal, cron reminders, preferences | 08, 13 |
| 16 | Occasions | CRUD, cron reminders, Claude AI messages | 06, 15 |
| 17 | Memory Book | Razorpay orders, PDF generation | 07, 15 |
| 18 | Search | Full-text search over transcriptions | 07, 09 |
| 19 | Admin Module | Analytics, user mgmt, feature flags | All |
| 20 | Health & Hardening | Health check, rate limits, error filter | All |
| 21 | Deployment | Railway + Supabase + R2 + OneSignal live | All |
| 22 | Flutter Integration | Wire app to real backend | 21 |
| 23 | Security Checklist | Final audit before users | 21, 22 |

---

*File generated: May 2026*
*Reference: BACKEND_ARCHITECTURE.md for schemas, API specs, and architectural decisions.*
*Stack: NestJS + TypeScript + PostgreSQL (Supabase) + Cloudflare R2 + Railway*
