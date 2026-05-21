# Saanjh — Complete Implementation Plan
### 34 Sequential Prompts · Covers All 65 Items · Zero Gaps
### Generated: 2026-05-17

---

## How This Works

Each section below is an **exact prompt** you copy-paste to Claude. 
Claude implements it completely before you move to the next.
They're ordered by dependency — each phase builds on the previous one.
**Do not skip phases.**

---

## PHASE 1 — Foundation & Cleanup
*Must happen first. Everything else depends on these.*

---

### Prompt 1 — Universal Model: Remove All Relationship-Specific Assumptions

```
Implement the universal relationship model shift in Saanjh.

1. Remove relationship_select_screen.dart from the onboarding navigation 
   flow in app_router.dart. The screen file can stay but it must not appear 
   in the onboarding sequence anymore. New onboarding order:
   Splash → OnboardingIntro → PhoneNumber → OtpVerify → NameEntry → Home

2. Audit and replace ALL hardcoded relationship-specific copy across every 
   screen file. Search for and replace:
   - Any hardcoded "Papa", "parent", "child", "family member" in UI strings
   - Replace with the contact's actual name variable where a name exists
   - Replace with neutral copy ("your person", "them", "someone you love") 
     where no specific name is available
   - The word "family" in section headers or labels → "people" or "connections"

3. In parent_invite_entry_screen.dart — repurpose it as a universal 
   invite_screen.dart. Same layout, new copy:
   - Title: "Invite someone to Saanjh"  
   - Sub: "They'll get a link to start a diary with you directly."
   - Remove any parent/child specific fields or copy
   - Keep the name + phone fields

4. In people_screen.dart — the _categorise() function and category labels 
   (Family/Friends/Partner/Others) should become user-defined labels, not 
   system-imposed. For now, keep the section headers but make them read as 
   optional display grouping only. Remove any logic that gates features 
   based on relationship category.

5. In DiaryContact model — the `relation` field stays but should be treated 
   as a freeform user-set label. Remove any code that treats specific 
   relation values as special (e.g. checking if relation == 'parent').

6. Update app_router.dart to rename the parentInvite route to just 'invite' 
   and update AppRoutes.parentInviteEntry to AppRoutes.invite. Update all 
   call sites.

Verify no "Papa" or relationship-specific strings remain in any UI-visible 
copy after this change.
```

---

### Prompt 2 — Data Layer: Enhance DiaryStore & DiaryContact for All New Features

```
Enhance the DiaryStore and DiaryContact model to support all upcoming 
features. Do not implement any UI yet — data layer only.

In diary_store.dart:

1. Add to DiaryContact model:
   - `customLabel: String` — user-set relationship label (default empty)
   - `avatarColorIndex: int` — index into a fixed 8-colour palette (default 
     derived from name hash as currently, but overridable)
   - `profileVoiceNotePath: String?` — path to a recorded intro note

2. Add to DiaryStore state:
   - `Map<String, Set<String>> _jarredEntries` — jarred (saved) entry IDs 
     per diary
   - `Map<String, int?> _milestoneReached` — last milestone value reached 
     per diary (null if none since last check)
   - `Map<String, bool> _streakJustBroke` — flag set when streak resets 
     from >1 to 1
   - `Map<String, bool> _justResumed` — flag set when first send after break
   - `Map<String, String?> _occasionTag` — active occasion tag per diary

3. Add methods to DiaryStore:
   - `jarEntry(String diaryId, String entryId)` 
   - `unjarEntry(String diaryId, String entryId)`
   - `isJarred(String diaryId, String entryId) → bool`
   - `jarredFor(String diaryId) → Set<String>`
   - `streakJustBroke(String id) → bool` (reads and clears the flag)
   - `justResumed(String id) → bool` (reads and clears the flag)
   - `clearMilestone(String id)`
   - `milestoneReached(String id) → int?`
   - `setOccasionTag(String id, String? tag)`
   - `occasionTag(String id) → String?`
   - `updateCustomLabel(String id, String label)`
   - `updateAvatarColorIndex(String id, int index)`
   - `momentsByMonth(String diaryId) → Map<String, List<String>>`

4. Update _recordSend() to:
   - Set _streakJustBroke[id] = true when streakDays resets from >1 to 1
   - Set _justResumed[id] = true when sending after a break
   - Check if new streakDays equals [7, 14, 30, 60, 90, 100, 365] and set 
     _milestoneReached[id] = days if so
   - Clear _streakJustBroke on any new send

5. Add DiaryEntry model class:
   ```dart
   class DiaryEntry {
     final String id;
     final String diaryId;
     final bool isMine;
     final String type; // 'voice' | 'video'
     final String path;
     final String? transcript;
     final String? prompt;
     final String? occasionTag;
     final DateTime createdAt;
     DateTime? listenedAt;
     double? moodEnergy;
     List<DiaryEntry> reactions;
     final String? parentEntryId;
   }
   ```
   Add `Map<String, List<DiaryEntry>> _entries` to DiaryStore.
   Add `addEntry(DiaryEntry entry)`, `markListened(String entryId)`,
   `updateEntryTranscript(String entryId, String transcript)`,
   `updateEntryMood(String entryId, double energy)`,
   `addReaction(String parentEntryId, DiaryEntry reaction)`,
   `entriesFor(String diaryId) → List<DiaryEntry>`,
   `removeEntry(String entryId)`.

6. Add `avatarPalette` static list of 8 Colors to DiaryContact.

7. Add `displayName` getter to DiaryContact: returns customLabel if set, 
   else name, else phone.

8. Add `bestSendStreak → int` to DiaryStore (alias for bestStreakDays).

9. Add `listenedAtLabel(String entryId) → String?` to DiaryStore.

10. Add `get diaryAnniversaries → Map<String, int>` to DiaryStore.
```

---

### Prompt 3 — Remove Deprecated Code & Screen Cleanup

```
Clean up all deprecated and redundant code from the Saanjh codebase.

1. Remove relationship_select_screen.dart route from app_router.dart 
   (keep file but comment out the route). Verify onboarding flows:
   Splash → OnboardingIntro → PhoneNumber → OtpVerify → NameEntry → Home

2. Remove any remaining references to:
   - PulseStreakTier enum (check all screen files)
   - Any imports of PulseStreakTier
   - Old _FreeBookUnlock widget remnants
   - Old _CountdownCard widget remnants

3. In app_router.dart — add the renamed 'invite' route pointing to the 
   repurposed InviteScreen. Remove the 'parentInvite' route name.

4. Search entire lib/ for: "parentInviteEntry", "parent_invite_entry", 
   "ParentInviteEntry". Rename screen class to InviteScreen.

5. Audit every screen file for unused imports. Remove any that reference 
   screens or classes that no longer exist.

6. In pubspec.yaml — verify all packages are still used.

7. Search for "TODO", "FIXME", "HACK" comments and list them 
   in a code comment block at the top of main.dart.

Verify the app compiles with no errors or warnings after cleanup.
```

---

## PHASE 2 — Onboarding Rewrite

---

### Prompt 4 — New Onboarding: Emotional Film Screen

```
Create the emotional onboarding film screen for Saanjh — the first thing 
a new user sees before any sign-up.

Create lib/frontend/screens/onboarding_film/onboarding_film_screen.dart

Animation sequence (CustomPainter + AnimationController, no images/Lottie):

Frame 1 (0–2s): Dark screen. Single warm amber light appears — a phone 
  screen glowing. Text fades in: "somewhere in the city…"
Frame 2 (2–4s): A waveform animates — someone recording a voice note. 
  Amber waveform, breathing gently.
Frame 3 (4–6s): Waveform travels as a line across the screen left to right.
Frame 4 (6–8s): Another phone screen on the right. Text: "somewhere they 
  remember you."
Frame 5 (8–10s): Both screens visible. Small ♥ between them, pulses once. 
  Both glow warm. Fade to black.
Frame 6 (10s): "Saanjh." in display serif font, amber, centred. 
  Sub: "A living diary with the people who matter." Stays 1.5s.

Controls:
- Skip button (top right, appears after 2s): small "Skip →" in textFaint
- Auto-advances after full sequence
- On complete or skip → PhoneNumberScreen

Update app_router.dart:
- Add route: AppRoutes.onboardingFilm = '/onboarding-film'
- Add first_launch check via SharedPreferences key 'has_seen_film'
  If not seen → show film first. If seen → skip to phone screen.
- Mark as seen after playing.

Use AppColors.emberWarm, AppColors.ink, AppTypography.display for final text.
```

---

### Prompt 5 — New Onboarding: Universal Connect Step

```
Replace the post-name-entry onboarding with a universal connect step.

Create lib/frontend/screens/connect_first/connect_first_screen.dart

Design:
- Header: "Who do you want to start a diary with?" in title(28) serifItalic
- Sub: "Pick from your contacts or invite them to join you." serifItalic(16)
- Two large equal cards:

  Card 1: "Find on Saanjh"
  - Icon: person_search_rounded in emberWarm
  - Sub: "See which of your contacts are already here"
  - Tap → contacts permission → DiscoverScreen

  Card 2: "Invite someone"
  - Icon: person_add_rounded
  - Sub: "Send them a link to join your diary"
  - Tap → InviteScreen (repurposed from parent_invite_entry)

- TextButton below: "I'll do this later →" → HomeScreen
- Footer: "You can add more people anytime from the app."

Update route flow:
- AppRoutes.connectFirst = '/connect-first'
- NameEntry "Continue" → ConnectFirst → Home

Update InviteScreen (repurposed parent_invite_entry):
- Title: "Invite [name] to Saanjh" OR "Invite someone you love"
- Share message template:
  "[YourName] wants to share a voice diary with you on Saanjh.
  Download it here → [link]
  Your diary together starts the moment you join."
- Remove all relationship type selection
- Keep name + phone fields

Create lib/frontend/screens/invite_accept/invite_accept_screen.dart:
- Shows when app opened via invite deep-link
- First screen: "[YourName] created a diary for you on Saanjh 💛"
- "Sign up with your number" — one step
- After auth: auto-creates diary → lands in that thread
- AppRoutes.inviteAccept = '/invite-accept'
- app_router.dart extracts inviterId from extras
```

---

## PHASE 3 — Core Activation Features (P0)

---

### Prompt 6 — Listener's Receipt: Complete Implementation

```
Implement the Listener's Receipt — when someone plays your voice note, 
you receive a signal. Highest-ROI retention feature.

1. In DiaryStore (from Prompt 2 data layer):
   Verify markListened(String entryId) and listenedAtLabel(String entryId) 
   are implemented and call notifyListeners().

2. In diary_thread_screen.dart _VoiceBubble:
   - When received (isMine: false) note starts playing → 
     DiaryStore.instance.markListened(entry.id)
   - For sent notes (isMine: true): show listened receipt below timestamp:
     - If listenedAt not null: "Listened ✓ 9:30 AM" in label(10.5) 
       Color(0xFF7CD992) — animated with AnimatedSwitcher from grey ✓
     - If null: existing grey "✓" tick

3. Create lib/frontend/widgets/notification_banner.dart:
   
   enum SaanjhNotificationType {
     listenerReceipt, pulseReceived, mutualPulse,
     streakAtRisk, streakBroke, milestone, onThisDay, occasion,
   }
   
   GlobalKey-accessible banner widget:
   - Slides down from top of screen
   - Auto-dismisses after 3000ms
   - Tappable → navigates to diaryId
   - show(String message, String? diaryId, SaanjhNotificationType type)
   - Visual: amber-tinted card with type-appropriate icon and colours
   - Uses AppMotion.medium for slide animation
   
   In HomeScreen → wrap Scaffold body with Stack, include 
   NotificationBanner as top Positioned overlay with a GlobalKey.

4. Trigger: in DiaryStore listener — when new listenedAt appears on a sent 
   entry, call NotificationBanner show with listenerReceipt type:
   "[Name] listened to your voice note · just now 💛"

5. In home_screen.dart _DiaryCard bottom row:
   Show "💛 listened" label (label 11, green) when most recent sent 
   entry has been listened to (lower priority than streak/pulse badges).
```

---

### Prompt 7 — Guided First Message: Prompt Cards

```
Implement guided first message experience for empty diary threads.

In diary_thread_screen.dart, replace _EmptyThread with a rich empty state:

1. Make _EmptyThread a StatefulWidget. Keep the सांझ display text and 
   "No moments yet." title. Add below them: 3 rotating prompt cards.

2. Static prompt list (shuffle, pick 3):
   - "Tell them what made you smile today 🌤"
   - "Share something that happened this week 💬"
   - "Say something you've been meaning to say 💛"
   - "What are you having for dinner? 🍛"
   - "What would you tell them if you called right now? 📞"
   - "Tell them one thing only they would understand ✨"

3. _PromptCard widget:
   - Amber-bordered card, serifItalic text centred
   - "Hold to record this →" in label(12) textFaint at bottom
   - Background: ember at 0.06 alpha, radius 20
   - PageView with 3 dot indicators

4. Tap/long-press prompt card:
   context.push(AppRoutes.voiceRecord, 
     extra: {'isVideo': false, 'autoStart': true, 'prompt': promptText})

5. In record_screen.dart:
   - Extract 'prompt' from extras
   - If provided: show amber chip above record button with prompt text 
     in serifItalic(14)

6. In DiaryStore.updateSnippet() — add optional prompt param:
   updateSnippet(String id, String snippet, String time, {String? prompt})

7. In _VoiceBubble — if entry has prompt, show small sepia label above 
   waveform: "💬 [prompt truncated to 30 chars]" in label(11) textFaint
```

---

### Prompt 8 — Streak Break Emotional Experience

```
Implement the streak break emotional experience.

1. Verify in DiaryStore:
   - streakJustBroke(String id) → bool reads and clears _streakJustBroke
   - justResumed(String id) → bool reads and clears _justResumed

2. In home_screen.dart _DiaryCard (inside ListenableBuilder):
   Add: final justBroke = DiaryStore.instance.streakJustBroke(d.id);
   
   justBroke == true visual state:
   - No avatar ring
   - Bottom-right: grey pill "◦ Start again" in label(11) textFaint
   - Card: default background (no warm tint)
   - Name: normal weight

3. In diary_thread_screen.dart _BottomActionBar — create _StreakBreakBanner:
   Show above _StreakAtRiskBanner when justBroke == true:
   - Background: Color(0xFF1A0800)
   - Border: amber 0.15 alpha
   - ♥ icon left + serifItalic(14) textMuted:
     "Your [N]-day streak paused. It's okay. [Name]'s still there."
   - Small amber TextButton "Record something now →" → calls onRecord
   - Dismissable with ✕ (local _breakBannerDismissed flag)
   - AnimatedSize like other banners

4. First send after break:
   Check DiaryStore.instance.justResumed(widget.diaryId):
   If true → show NotificationBanner:
   "You're back 💛 Day 1 with [Name]" in amber, 2s auto-dismiss.

5. Update _StreakBadge across all screens:
   - streakDays == 0 && !justBroke → no badge
   - justBroke → "◦ Start again" grey pill
   - atRisk → "⏳ N" red pill
   - hasSentToday → "🔥 N" amber pill
   - !hasSentToday && !atRisk → "🔥 N" faint amber pill
```

---

## PHASE 4 — Emotional Core & Retention (P1)

---

### Prompt 9 — Streak Milestone Celebrations

```
Implement streak milestone celebrations at 7, 14, 30, 60, 90, 100, 365 days.

1. Verify DiaryStore.milestoneReached(String id) → int? returns and clears.

2. Create lib/frontend/screens/streak_milestone/streak_milestone_screen.dart:
   - Full-screen dark with breathing tree emoji (AnimationController scale)
   - Confetti burst (reuse _BurstPainter style from pulse_screen.dart)
   - Large milestone number "🔥 47" in display font, amber
   - Milestone label in serifItalic(22):
     7  → "Your first week. Keep going. 🌿"
     14 → "Two weeks of showing up. 🌿"
     30 → "One month. [Name] has heard your voice every day. 🌲"
     60 → "Deep roots. You've built something real. 🎋"
     90 → "In full bloom. A free Memory Book is yours. 🌸"
     100 → "100 days of presence. This is extraordinary. 🌸"
     365 → "A full year. Your voices are woven into each other's lives. 🌸✨"
   - "with [Name]" below label
   - Two buttons: "Share this milestone →" | "Continue"
   - Route: AppRoutes.streakMilestone = '/streak-milestone'
   - Params: diaryId, contactName, milestoneValue

3. In home_screen.dart _DiaryCard ListenableBuilder:
   final milestone = DiaryStore.instance.milestoneReached(d.id);
   If milestone != null → WidgetsBinding.instance.addPostFrameCallback:
   context.push(AppRoutes.streakMilestone, extra: {
     'diaryId': d.id, 'contactName': d.displayName, 'milestone': milestone
   });

4. For milestones 7 and 14 — card-level confetti:
   _StreakMilestoneBurst: positioned overlay on card, 600ms particle burst.
   In _DiaryCardState: _showBurst bool, triggered by milestone check.

5. If streak >= 30: diary thread header gets amber 0.04 alpha gradient overlay.
   If streak >= 90: streak chip in header uses golden-amber gradient border.
```

---

### Prompt 10 — On This Day Resurfacing

```
Implement "On This Day" — highest-ROI retention mechanic.

1. Create lib/frontend/services/on_this_day_service.dart:
   class OnThisDayService {
     static OnThisDayService instance = OnThisDayService._();
     DiaryEntry? checkToday() — searches all DiaryStore entries for 
       month+day match, excludes current year, returns most recent match
     String yearLabel(DiaryEntry entry) — "1 year ago" / "2 years ago"
     String contactName(DiaryEntry entry) — looks up contact name
   }

2. Create lib/frontend/widgets/on_this_day_banner.dart:
   Golden banner card:
   - Background: Color(0xFF3A2200) → Color(0xFF1A0C00) gradient
   - Left: 4px golden vertical line Color(0xFFFFB800)
   - "ON THIS DAY · [N] year(s) ago" eyebrow in Color(0xFFFFB800)
   - "[Contact name] said something to you." serifItalic(16)
   - "▶ Play · [duration]" amber inline play button
   - ✕ dismiss (stored in SharedPreferences by date)
   - Plays voice note INLINE (no navigation) — mini waveform player
   - AnimatedSize entrance

3. In DiaryStore: 
   DiaryEntry? get onThisDayEntry — checks once per day via SharedPreferences,
   runs OnThisDayService.checkToday(), caches result.

4. In home_screen.dart _DiariesTabState.build():
   If onThisDayEntry != null && !_isSelecting && _query.isEmpty:
   Show OnThisDayBanner above search bar.

5. Create lib/frontend/screens/on_this_day/on_this_day_screen.dart:
   - Lists all historical matches for today across all years
   - Calendar browse capability
   - Route: AppRoutes.onThisDay = '/on-this-day'
   - "View all" link from banner navigates here
```

---

### Prompt 11 — Morning Minute Ritual

```
Implement the Morning Minute ritual (app open before 9 AM).

1. Create lib/frontend/services/morning_service.dart:
   - isMorning → bool: hour >= 5 && hour < 9
   - isFirstOpenToday → bool: SharedPreferences last open date check
   - markOpened() — stores today's date
   - morningGreeting → String: time-based greeting copy

2. Create lib/frontend/widgets/morning_overlay.dart — MorningOverlay widget:
   Full-screen bottom sheet (isScrollControlled: true):
   - Subtle amber radial gradient background (ember 0.08 alpha)
   - Current time in display(48) centred
   - serifItalic greeting (time-based):
     5–6 AM: "Up early. Someone will love hearing that. 🌙"
     6–7 AM: "Good morning. The day is just beginning. 🌅"
     7–8 AM: "Morning light. A good time to say something. ☀️"
     8–9 AM: "Good morning. Before the day gets busy."
   - If pulse not sent: smaller hold button (80px) + "Hold to say you're here"
   - If received pulse: "[Name] was here at [time]. 💛" large centred
   - "Continue to diaries" TextButton at bottom
   - "Today I'm feeling..." row: mic icon + text → RecordScreen 
     with isPrivateReflection: true

3. In home_screen.dart _HomeScreenState.initState() postFrameCallback:
   If MorningService.instance.isMorning && isFirstOpenToday:
   showModalBottomSheet with MorningOverlay.
   Call markOpened().

4. Create lib/frontend/services/personal_reflection_service.dart (stub):
   Stores private voice recordings locally. 
   Never shared. Only accessible from Me screen.
   Will be fully implemented in Prompt 27.
```

---

### Prompt 12 — Pulse Completion Ritual

```
Implement the pulse completion ritual — closing ceremony after sending.

In pulse_screen.dart:

1. Add _ritualCtrl: AnimationController (600ms) to _PulseScreenState.
   Add _showRitual: bool = false state flag.

2. After _store.sendPulseToMany() — before setState(_phase = _Phase.sent):
   _showRitual = true → _ritualCtrl.forward()
   .whenComplete(() => setState(() { _showRitual = false; _phase = _Phase.sent; }))

3. Single-person ritual overlay (Positioned.fill, only when _showRitual):
   - Amber wash: ember colour, alpha 0.0 → 0.15 → 0.0 over 600ms
   - Centred text fades in at 200ms:
     "[Name] will know you were here today." in display(28) serifItalic amber
   - Haptic: mediumImpact → 80ms delay → lightImpact (lub-dub)

4. Multi-person ritual:
   - Same amber wash, 0.20 peak alpha
   - "They'll all know you were here today. 💛"

5. Mutual pulse ritual (isMutualToday for any selected contact):
   - Green wash Color(0xFF30D158) at 0.12 alpha
   - "You're both here today. ♥" in Color(0xFF7CD992)
   - Two concentric circles expanding from centre in green

6. "Opens again at midnight" hint: delay its appearance until 
   _ritualCtrl completes + burst time.

7. Burst painter still plays during ritual — overlay sits on top.
```

---

### Prompt 13 — Memory Jar

```
Implement the Memory Jar — save favourite voice moments, resurface randomly.

1. Verify DiaryStore has jar methods from Prompt 2.

2. In diary_thread_screen.dart _VoiceBubble — add long-press context menu:
   GestureDetector with onLongPress → showModalBottomSheet (_VoiceBubbleContextSheet):
   - "✨ Save to Memory Jar" / "✓ Saved · Remove from Jar"
   - "Share this moment →" (stub — Prompt 33 implements)
   - "Copy transcript" (clipboard if transcript exists)
   - "Delete" (red, isMine only)
   
   "Save to Memory Jar" → DiaryStore.instance.jarEntry(diaryId, entry.id)
   → NotificationBanner.show("✨ Saved to your Memory Jar")

3. Jarred bubble indicator: tiny ✨ (size 10) amber at bottom-left of bubble.

4. In me_screen.dart — add _MemoryJarSection:
   - Header: "✨ MEMORY JAR" with hairline rule
   - Empty: serifItalic(15) "Long-press any voice note to save it here."
   - Entries: horizontal scroll of amber-bordered contact+duration chips
   - "View all →" → MemoryJarScreen

5. Create lib/frontend/screens/memory_jar/memory_jar_screen.dart:
   - All jarred entries across all diaries, grouped by contact
   - Each: avatar, name, duration, date, play button
   - Long-press → remove from jar option
   - Route: AppRoutes.memoryJar = '/memory-jar'

6. Random jar memory on home open:
   In _HomeScreenState.initState() postFrameCallback:
   1 in 5 chance (Random().nextInt(5) == 0), if jar has entries:
   Show NotificationBanner: "✨ A memory from your jar — [Name], [date]"
   Only if !MorningService.instance.isMorning (don't compete with morning ritual).
```

---

### Prompt 14 — Occasion-Triggered Templates

```
Implement occasion-triggered templates for high-emotion days.

1. Create lib/frontend/services/occasion_service.dart:
   OccasionCalendar: static list of 20 occasions (Diwali, Eid, Christmas,
   New Year, Republic Day, Independence Day, Mother's Day, Father's Day,
   Holi, Raksha Bandhan, Navratri, Baisakhi, Onam, Pongal, Valentine's Day,
   Friendship Day, Teacher's Day, Grandparents Day, New Year's Eve, Dussehra)
   
   Each: name, emoji, month, approximateDay, daysBeforeToShow: 2
   
   upcomingOccasion() → Occasion? if today is within daysBeforeToShow days.
   
   occasionPrompt(Occasion, String contactName) → String warm copy like:
   "Diwali is in 2 days. Send [contactName] a greeting before the forwards 
   start. 20 seconds. It'll mean more. 🪔"

2. Create _OccasionBanner widget in home_screen.dart:
   Shows between search bar and pulse strip when occasion upcoming:
   - Occasion-appropriate tint background (Diwali: deep gold, Christmas: deep red)
   - Occasion emoji (size 28) left
   - Prompt copy with actual contact name (highest-streak diary)
   - "Record a greeting →" amber button
   - ✕ dismiss (SharedPreferences: occasion name + year)
   
   Tap → RecordPickerSheet in voice mode with
   extra: {'occasionTag': '[emoji] [occasion name]'}

3. In RecordScreen when occasionTag extra provided:
   Show occasion chip above record button: tinted container + emoji + name

4. In RecordScreen._send() with occasionTag:
   Call DiaryStore.instance.setOccasionTag(id, occasionTag)

5. In diary_thread_screen.dart _VoiceBubble:
   If entry.occasionTag not null: small amber chip above waveform showing tag.

6. In home_screen.dart _DiariesTabState.build():
   Check OccasionService.instance.upcomingOccasion() — if non-null &&
   !_isSelecting && _query.isEmpty: show _OccasionBanner between 
   search bar and pulse strip. Occasion banner shows above OnThisDay banner.
```

---

### Prompt 15 — Relationship Weather Ambient Signal

```
Implement relationship weather — ambient activity health signal on diary cards.

1. Add to DiaryStore:
   enum DiaryWeather { sunny, partlyCloudy, overcast, quiet, clearingUp }
   
   DiaryWeather weatherState(String id) {
     if (hasSentToday(id) && streakDays(id) > 0) return sunny;
     if (streakAtRisk(id)) return partlyCloudy;
     if (justResumed(id)) return clearingUp;
     final last = _lastSentDate[id];
     if (last == null) return overcast;
     final gap = DateTime.now().difference(last).inDays;
     if (gap >= 7) return quiet;
     if (gap >= 3) return overcast;
     return partlyCloudy;
   }

2. In home_screen.dart _DiaryCard — read weather:
   final weather = DiaryStore.instance.weatherState(d.id);
   
   Card visual modifiers:
   - sunny: existing amber (already handled by streak) — no change
   - clearingUp: one-shot border colour AnimationController amber→green→amber
   - partlyCloudy: no change
   - overcast: reduce ember background alpha slightly
   - quiet: card to inkRaised background + "🌧 Quiet lately · say something?" 
     serifItalic(11) textFaint replacing streak badge

3. In diary_thread_screen.dart _ThreadHeader subtitle row:
   - sunny: keep amber streak label
   - quiet: "🌧 Quiet lately · say something?" textFaint
   - clearingUp: "🌤 Back together 💛" ember for 24h after resuming

4. clearingUp shimmer: _shimmerCtrl (1000ms one-shot) in _DiaryCardState.
   Animate border: ColorTween amber → green → amber. One play only.
   Store 'seen_clearing_up_[id]' locally to prevent repeat.
```

---

### Prompt 16 — Bottom Navigation Restructure

```
Restructure bottom navigation: add Pulse as permanent dedicated tab.

New tabs: Diaries (0) · Pulse (1) · Memories (2) · Me (3)

1. Update _BottomNav items in home_screen.dart:
   - 0: Diaries — chat_bubble icons (unchanged)
   - 1: Pulse — favorite_rounded/favorite_border_rounded, emberWarm colour
   - 2: Memories — auto_awesome icons (renamed from "Moments")
   - 3: Me — person icons (unchanged)

2. Update PageView children:
   0: _DiariesTab (unchanged)
   1: PulseScreen(isEmbedded: true)
   2: MemoryTreeScreen(isEmbedded: true)
   3: MeScreen(isEmbedded: true)

3. Add isEmbedded: bool param to PulseScreen:
   When true: hide back button / show app wordmark instead.
   Otherwise identical behaviour.

4. Remove People tab. People accessible via:
   - person_search icon in diaries header (opens DiscoverScreen)
   - Me tab → "Your Connections" nav row

5. In me_screen.dart — add "Your Connections" _NavRow in ACCOUNT section:
   icon: people_outline_rounded
   label: 'Your connections'
   sub: '${DiaryStore.instance.diaries.length} people'
   onTap: () => context.push(AppRoutes.people)

6. Update _onNavTap and _pageCtrl for 4 new tabs.
   FAB only shows on Diaries tab (index 0) — unchanged.
```

---

### Prompt 17 — Enhanced Memory Tree

```
Enhance Memory Tree: seasonal, interactive, per-diary, health signal.

In memory_tree_screen.dart:

1. Seasonal changes in _TreePainter:
   Add: season param (from DateTime.now().month), leafDensity: double
   Spring (3-5): leaf RGB(180, 220, 120), density 0.7
   Summer (6-8): leaf RGB(60, 160, 80), density 1.0
   Autumn (9-11): leaf RGB(220, 120, 40), density 0.5
   Winter (12-2): bare, density 0.0, occasional white particle dots
   
   Falling leaf particles (Autumn): 3-5 Offsets drifting down with breatheCtrl.

2. Interactive month branches:
   _tappableBranches: List<Rect> computed in paint(), passed via callback.
   GestureDetector.onTapDown on _TreeCanvas:
   Check which branch Rect contains tap → show _MonthDetailSheet.
   
   _MonthDetailSheet: lists DiaryEntry snippets for that month.
   Each: contact name, type icon, duration, date, play button.
   Use DiaryStore.momentsByMonth(diaryId).

3. Per-diary trees:
   Add optional diaryId param to MemoryTreeScreen.
   When set: header "[Name]'s Memory Tree", only show that diary's entries.
   
   Update diary_thread_screen.dart _ThreadHeader park icon:
   context.push(AppRoutes.memoryTree, extra: {'diaryId': widget.diaryId})
   Update app_router.dart to extract optional diaryId.

4. Tree health signal:
   health param (0.0–1.0) in _TreePainter:
   1.0 sent today + active streak, 0.7 active but not today,
   0.3 one-week gap, 0.0 two-week+ gap.
   Health scales leafDensity and branch thickness.

5. Empty tree:
   Single breathing seed at tree base (12px circle, ember, breatheCtrl).
   "Plant the first memory." serifItalic(16) textMuted below.
   Tap → navigate to diary thread or record screen.
```

---

### Prompt 18 — Empty States Redesign (All Screens)

```
Redesign all empty states to tell a story and invite action.

1. Create lib/frontend/widgets/saanjh_empty_state.dart:
   Parameters: Widget? visual, String title, String? body,
   String? ctaLabel, VoidCallback? onCta
   Standard layout: visual centred, title title(22), body serifItalic(16),
   CTA amber gradient button.

2. Empty diary list (home_screen.dart _EmptyState):
   Keep existing content. Add: animated amber pulse rings expanding outward
   below the logo (CustomPainter, 2 rings, 3s cycle, represents "people waiting").
   Add secondary "Invite someone →" TextButton.

3. Empty People tab (people_screen.dart _EmptyState):
   Visual: two abstract rounded-rect silhouettes (white 0.3 alpha) leaning 
   toward each other, small amber ♥ floating between them. CustomPainter.
   Title: "Your people are one tap away."
   Sub: "Find who's on Saanjh or invite someone you love."
   CTA: "Find connections →" → DiscoverScreen

4. Empty Memory Tree (memory_tree_screen.dart):
   Single breathing seed at tree base position (breatheCtrl existing).
   "Plant your first memory." serifItalic(16)
   "Start a diary →" TextButton
   Filter-empty: "No [voice/video] moments yet. Record from a diary."

5. Empty Memory Jar (memory_jar_screen.dart):
   Jar outline CustomPainter (oval body, small neck, lid) amber strokes 
   0.3 alpha, breathing gently.
   Title: "Your jar is empty."
   Sub: "Long-press any voice note and save it here. ✨"

6. Empty pulse strip: stays hidden (SizedBox.shrink()) — correct, keep.

7. No connections on pulse screen (ready state):
   Below hold button: "Add someone to start pulsing." serifItalic(15)
   "Add →" amber TextButton → ConnectFirst screen.

8. All existing screens should use SaanjhEmptyState as their base widget.
```

---

### Prompt 19 — Voice Note Bubble Redesign

```
Redesign voice note bubbles: transcripts, end-cards, context menus, speed.

In diary_thread_screen.dart:

1. Playback speed toggle:
   Add _playbackSpeed: double (1.0 / 1.5) to _DiaryThreadScreenState.
   In _VoiceBubble: small speed button bottom-right of waveform:
   Text("${speed}×") label(10) w700. Tap → toggle speed.
   Visual only for now. TODO: wire to audio player when backend added.

2. Transcript preview (entry.transcript may be null until Prompt 22):
   If entry.transcript != null:
   Below waveform row: first 60 chars in serifItalic(13) textMuted.
   If longer: "... more" label(11) textFaint → AnimatedSize expand.
   Collapsed by default.

3. Voice note end-card:
   Add _showEndCard: bool and _endCardEntryIdx: int? to screen state.
   When _playCtrl completes:
   setState(() { _showEndCard = true; _endCardEntryIdx = idx; })
   After 3000ms: setState(() { _showEndCard = false; _playingIdx = null; })
   
   _VoiceBubble: when isShowingEndCard:
   AnimatedSwitcher → _EndCard:
   - "[contact first name]'s voice" label(11) textFaint
   - Duration serifItalic(22) amber centred
   - Date label(11) textFaint
   - "↻ Play again" | "🎙 Record back" TextButtons

4. Context menu long-press (extend from Prompt 13):
   _VoiceBubbleContextSheet includes:
   - "✨ Save to Memory Jar" (from Prompt 13)
   - "Share this moment →" (stub — Prompt 33)
   - "Copy transcript" (clipboard if transcript exists)
   - "Delete" (red, isMine only — DiaryStore.removeEntry())

5. Listened receipt: verify from Prompt 6 — "Listened ✓ 9:30 AM" 
   AnimatedSwitcher from grey ✓ to green.

6. Richer bubble background:
   For received (isMine: false) notes:
   Stack with Positioned.fill: contact.avatarColor at 0.05 alpha.
   Gives each person's notes a faint unique tint.
```

---

### Prompt 20 — Profile Personalisation

```
Implement profile personalisation: custom labels, colours, status.

1. Custom diary labels (displayName getter from Prompt 2):
   In diary_thread_screen.dart _ThreadHeader — small ✏ icon (size 12, 
   textFaint) next to contact name. Tap → TextField bottom sheet.
   Call DiaryStore.instance.updateCustomLabel(id, label).
   All places showing contact name: use contact.displayName instead of name.

2. Custom avatar colour picker:
   avatarPalette already added in Prompt 2 (8 colours).
   In diary_thread_screen.dart — long-press contact avatar in header:
   Colour picker bottom sheet: 8 circles in a Row.
   Selected shows ✓. Tap → DiaryStore.instance.updateAvatarColorIndex(id, i).
   DiaryContact.avatarColor getter: use palette[avatarColorIndex] if set,
   else existing hash-based colour.
   Also accessible from me_screen.dart profile edit.

3. Status line:
   In UserStore: _status: String, setStatus(String), get status.
   In me_screen.dart _ProfileHero below name:
   If status set: serifItalic(14) textMuted
   If not: "Set a status..." tappable textFaint italic(14)
   Tap → TextField bottom sheet, max 50 chars.

4. In discover_screen.dart contact tile:
   If contact has custom label → show label instead of phone number.

5. In people_screen.dart _PersonTile:
   Show contact.displayName (uses customLabel if set) everywhere.
   Relation field becomes a "label" shown as optional metadata below name.
```

---

## PHASE 5 — Growth & Polish (P2)

---

### Prompt 21 — Shareable Milestone Cards

```
Implement shareable milestone cards for streak achievements.

Add to pubspec.yaml: share_plus: ^10.1.2, path_provider: ^2.1.4

1. Create lib/frontend/widgets/milestone_share_card.dart:
   Off-screen rendered widget with RepaintBoundary + GlobalKey.
   400×700 logical pixels:
   - Background: Color(0xFF2A0E00) → Color(0xFF0A0400) gradient
   - Tree emoji large (size 80) centred
   - "🔥 [N]" in display(72) amber  
   - "[N] mornings with [Name]" serifItalic(24) white
   - Milestone label serifItalic(18) textMuted
   - Decorative faded waveform behind number
   - "Saanjh · saanjh.app" small watermark bottom

2. Create lib/frontend/services/share_card_service.dart:
   shareStreakCard(GlobalKey cardKey, int streakDays, String contactName):
   - RenderRepaintBoundary.toImage(pixelRatio: 3.0)
   - toByteData(format: ImageByteFormat.png)
   - Write to temp file via path_provider
   - Share.shareXFiles([XFile(path)], text: '[N] mornings with [Name] on Saanjh 🔥')
   
   shareVoiceCard(GlobalKey cardKey, String contactName):
   - Same capture → share flow
   - Text: "A moment from [contactName] on Saanjh 🎙 · saanjh.app"

3. In streak_milestone_screen.dart (Prompt 9):
   Add Offstage(child: MilestoneShareCard(key: _cardKey, ...))
   "Share this milestone →" → ShareCardService.shareStreakCard()

4. In me_screen.dart:
   If bestStreakDays > 7: amber TextButton "Share your streak →" in _ProfileStats.
   Generates card for highest-streak diary.

5. In diary_thread_screen.dart _MoreMenuSheet:
   "Share [N]-day streak" option if streakDays > 0.
```

---

### Prompt 22 — Voice Transcription Foundation

```
Implement voice transcription infrastructure.

Add to pubspec.yaml: speech_to_text: ^7.0.0

1. Create lib/frontend/services/transcription_service.dart:
   class TranscriptionService {
     static TranscriptionService instance = TranscriptionService._();
     // STUB: Returns null. Real implementation: Whisper API via backend.
     Future<String?> transcribeFile(String audioPath) async => null;
   }
   Document: "Replace stub with POST to /api/transcribe when backend ready."

2. In record_screen.dart _send():
   Create DiaryEntry and call DiaryStore.instance.addEntry():
   DiaryEntry(
     id: DateTime.now().millisecondsSinceEpoch.toString(),
     diaryId: targetId,
     isMine: true,
     type: _mode == _Mode.voice ? 'voice' : 'video',
     path: _recordedFile?.path ?? '',
     transcript: null,
     prompt: extras['prompt'] as String?,
     occasionTag: extras['occasionTag'] as String?,
     createdAt: DateTime.now(),
   )
   Then async: TranscriptionService.instance.transcribeFile(path).then((t) {
     if (t != null) DiaryStore.instance.updateEntryTranscript(entry.id, t);
   });

3. _VoiceBubble: use DiaryEntry object instead of _Entry. Show transcript 
   preview from Prompt 19 (null handled gracefully = shows nothing).

4. Search integration in home_screen.dart _DiariesTabState._filtered:
   When _query non-empty: also search entry transcripts via 
   DiaryStore.instance.entriesFor(id). Match → include diary in results.
   Show matching transcript excerpt as card snippet.
```

---

### Prompt 23 — Design System Codification

```
Codify the Saanjh design system into reusable shared components.

1. Create lib/frontend/theme/app_spacing.dart with AppSpacing constants:
   xs=4, s=8, m=12, l=16, xl=20, xxl=24, xxxl=32, xxxxl=48

2. Update app_typography.dart — add height to all styles:
   display: 1.1, title: 1.15, body: 1.4, label: 1.3, serifItalic: 1.5

3. Create lib/frontend/widgets/saanjh_avatar.dart — SaanjhAvatar:
   Params: contact, size(52), showRing(bool), onTap, showGroupBadge, 
   showSelectionOverlay, isSelected.
   Reads PulseStore + DiaryStore internally for ring state.
   Replace all avatar+ring constructions in:
   home_screen.dart, people_screen.dart, create_group_screen.dart, 
   pulse_screen.dart

4. Create lib/frontend/widgets/saanjh_sheet.dart — SaanjhSheet:
   Params: title: String?, child: Widget, maxHeightFraction: double(0.82)
   Wraps with: ConstrainedBox, dark Container, Column(handle + title + 
   Flexible(SingleChildScrollView(child)) + SafeArea bottom padding).
   Refactor all bottom sheets to use SaanjhSheet.

5. Create lib/frontend/widgets/saanjh_badge.dart:
   - SaanjhStreakBadge(days, atRisk, sentToday)
   - SaanjhPulsedYouBadge(timeLabel)
   - SaanjhMutualBadge()
   - SaanjhWeatherBadge(weather)
   Replace all badge instances across home/people/create_group.

6. Replace hardcoded spacing values with AppSpacing constants in:
   diary_thread_screen.dart, pulse_screen.dart, home_screen.dart, 
   me_screen.dart (where values match AppSpacing definitions).
```

---

### Prompt 24 — Loading States & Skeleton Screens

```
Implement loading and skeleton states.

Add to pubspec.yaml: shimmer: ^3.0.0

1. Create lib/frontend/widgets/saanjh_shimmer.dart:
   SaanjhShimmer({Widget child, bool isLoading}):
   When loading: Shimmer.fromColors(baseColor: AppColors.inkRaised, 
   highlightColor: AppColors.ink)
   When not: shows child.

2. Diary list skeleton (_DiaryListSkeleton in home_screen.dart):
   5 fake _DiaryCard-shaped shimmer containers.
   Add _isLoading bool to DiaryStore (true 500ms on first load).
   Show skeleton while loading.

3. Pulse strip skeleton (_PulseStripSkeleton):
   4 shimmering 50px circles in a row.

4. Discover screen: Replace CircularProgressIndicator in _LoadingView with 
   5 shimmering _PersonTile-shaped skeletons.

5. Voice note loading state: shimmer waveform bars when entry loading.

6. Memory Tree reveal animation:
   Add _treeRevealCtrl: AnimationController (1200ms) in screen state.
   Pass revealProgress (0.0→1.0) to _TreePainter.
   Painter draws: trunk (0.0–0.3) → branches (0.3–0.7) → leaves (0.7–1.0).
   
7. Record screen camera init: add pulsing amber ring (48px, 0.3 alpha, 
   breathing) around camera area while initialising, replaces plain text.
```

---

### Prompt 25 — Accessibility Pass

```
Implement comprehensive accessibility across the app.

1. Semantics wrappers:
   SaanjhAvatar (Prompt 23): Semantics(label: '[Name] avatar. [N] day streak. 
   [Pulsed you today.]', button: onTap != null)
   _HoldButton: Semantics(label: 'Hold to send pulse', button: true)
   _RecordCard: Semantics(label: 'Record a voice/video note', button: true)
   _PulseButton: Semantics(label: 'Send pulse to [name]', button: true)
   All IconButton instances: ensure tooltip param is set.

2. Text scaling (do NOT override textScaler):
   Remove any textScaleFactor overrides from all files.
   Test at scale 1.5 — fix overflows by:
   - min-height instead of fixed height
   - Flexible/Expanded appropriately
   - TextOverflow.ellipsis where bounded
   - FittedBox on numeric displays

3. Touch targets (minimum 44×44px):
   _IconBtn in diary_thread_screen.dart: wrap 36×36 with SizedBox(44,44)
   All close buttons in sheets: same treatment.
   Use ExcludeSemantics on decorative elements.

4. Pulse tap mode for motor-impaired:
   In SettingsScreen → Accessibility section → "Tap instead of hold for Pulse"
   Toggle stored in SharedPreferences: 'pulse_tap_mode'
   In _HoldButton: if tapMode → onPanDown immediately triggers _complete().
   Show "(Tap mode)" label below button.

5. Colour contrast:
   Check AppColors.emberBright on AppColors.inkDeep.
   If below 4.5:1 WCAG AA → add AppColors.emberAccessible = Color(0xFFFFA040)
   and use it for small text in streak badges, strip labels, subtitle text.
```

---

### Prompt 26 — Memory Reactions

```
Implement Memory Reactions — voice note reactions to old memories.

1. DiaryEntry already has reactions: List<DiaryEntry> and parentEntryId: String?

2. DiaryStore.addReaction(String parentEntryId, DiaryEntry reaction):
   Finds parent entry, adds reaction to its reactions list, notifyListeners.

3. In memory_tree_screen.dart _MonthDetailSheet (Prompt 17):
   Each memory item: "React with your voice 🎙" TextButton.
   Tap → RecordScreen with extras:
   {'isVideo': false, 'autoStart': true, 'parentEntryId': entry.id,
    'reactionContext': 'Reacting to a memory from [month label]'}
   
   RecordScreen: if parentEntryId in extras:
   Show context banner: "Reacting to a memory from [date]" amber-bordered.
   On _send(): DiaryStore.instance.addReaction(parentEntryId, newEntry).

4. In _TreePainter: entries with reactions get a small ✦ marker on their 
   node (4-pointed star, amber, 6px).

5. In memory detail sheet: 
   "Reactions ([N])" expandable section below entries with reactions.
   Each reaction: mini voice bubble (padding 10, text size 12).

6. In memory_jar_screen.dart: same "React" option on jarred entries.
```

---

### Prompt 27 — Personal Reflection Journal

```
Implement the Personal Reflection Journal — private voice notes, 
never shared, played back 1 year later.

1. Create lib/frontend/state/personal_reflection_store.dart:
   class PersonalReflection { id, audioPath, transcript?, createdAt, prompt? }
   class PersonalReflectionStore extends ChangeNotifier {
     static final instance = PersonalReflectionStore._();
     List<PersonalReflection> _reflections = [];
     void addReflection(PersonalReflection r)
     PersonalReflection? todaysMemory() — month+day match, year-1
     List<PersonalReflection> get all → sorted desc
   }

2. In record_screen.dart with isPrivateReflection: true extras:
   - Deep indigo/purple tint instead of amber (private feel)
   - Replace "🎙 Send this note →" with "Save to my journal →"
   - On _send() → PersonalReflectionStore.instance.addReflection()
   - Show "This is just for you. No one else can hear this. 🔒" 
     label(12) textFaint below record button.

3. In me_screen.dart _PersonalJournalSection (add below _MemoryJarSection):
   - Header: "🔒 MY JOURNAL" with hairline rule
   - If todaysMemory(): golden banner "A year ago today, you recorded 
     something 🎙" + play button
   - Count: "[N] private reflections" label(13)
   - "Add today's →" TextButton → RecordScreen isPrivateReflection: true
   - "View all →" → PersonalJournalScreen

4. Create lib/frontend/screens/personal_journal/personal_journal_screen.dart:
   Lists all personal reflections newest first.
   Each: date, duration, play button. No contact names.
   Header: "My Journal · Private" with lock icon.
   Route: AppRoutes.personalJournal = '/personal-journal'

5. OnThisDayService.checkToday(): also check PersonalReflectionStore.
   If match: secondary banner "A year ago, you recorded a private 
   reflection. → Listen" with 🔒 icon.

6. Verify morning_overlay.dart "Today I'm feeling..." opens RecordScreen 
   with isPrivateReflection: true (from Prompt 11 stub).
```

---

### Prompt 28 — Group Family Diary Enhancement

```
Enhance group diaries into proper Family Spaces.

1. Add to DiaryContact:
   members: List<DiaryContact> (group members, default empty)
   elderMemberId: String? (designated Elder)
   Update isGroup: has members && members.length > 1.
   
   For testing: auto-populate members from DiaryStore contacts 
   when a group diary is created.

2. In group_thread_screen.dart _GroupHeader — make dynamic:
   Stack mini avatars from d.members (max 3, then "+N more").
   Elder member gets small 👑 badge at top-right of their mini avatar.
   Member count: "${d.members.length} members".
   Pulse count: "${pulsedCount} here today" if any members pulsed.

3. Group pulse row below header:
   Thin row: each member tiny avatar (28px) with amber ring if pulsed today.
   "N/M here today" count.
   Tap → PulseScreen with group member IDs as targets.

4. Member name labels on bubbles:
   For isMine: false bubbles: label(11) in sender.avatarColor above bubble.
   Left-aligned. Shows sender's displayName.

5. Empty group state (_EmptyGroup):
   3 stacked abstract silhouettes.
   "Start the family diary. Who goes first?"

6. In create_group_screen.dart _CreateGroupForm:
   After member selection: "Designate an Elder (optional)" section.
   Small member selector → set elderMemberId.
   Elder visual description shown.
```

---

### Prompt 29 — Notification Architecture

```
Implement complete notification architecture.

1. Extend lib/frontend/widgets/notification_banner.dart:
   Add SaanjhNotificationType enum with all types.
   Update NotificationBanner to render type-appropriately:
   - listenerReceipt: ♥ green
   - pulseReceived: amber dot
   - mutualPulse: ♥♥ green
   - streakAtRisk: ⏳ red text
   - streakBroke: soft amber
   - milestone: 🔥 golden
   - onThisDay: 📅 sepia gold
   - occasion: occasion emoji warm

2. Create lib/frontend/services/notification_service.dart:
   Centralized trigger management. Listens to DiaryStore + PulseStore.
   Methods: handleStoreChange(), _checkListenerReceipts(), 
   _checkPulseReceived(), _checkStreakMilestones(), _checkStreakBreaks().
   Connect to stores in HomeScreen.

3. Add comprehensive push notification spec as comment block including:
   All 8 trigger types with:
   - Title template
   - Body template  
   - Data payload
   - Action buttons
   - Deep-link target
   - Rate limiting rules (max 3/day per user)
   - NotificationPreferences respect
   
   Mark clearly: "/* PUSH NOTIFICATION SYSTEM — implement when backend ready */"
```

---

### Prompt 30 — The First Year Memory Book Foundation

```
Implement Memory Book foundation — retention and revenue cornerstone.

1. Create lib/frontend/services/memory_book_generator.dart:
   class MemoryBookPage { contactName, date, transcript?, occasionTag?, 
   isMine, durationSeconds }
   
   class MemoryBookData { contactName, totalEntries, totalDurationSeconds,
   peakStreak, totalPulses, pages: List<MemoryBookPage>, firstEntryDate,
   lastEntryDate, totalHoursFormatted, durationLabel }
   
   class MemoryBookGenerator {
     static MemoryBookData? generateForDiary(String diaryId)
     static MemoryBookData? generateAnnual()
   }

2. Update memory_book_screen.dart with real data:
   Call MemoryBookGenerator.generateForDiary() or generateAnnual().
   If null → "Your Memory Book will be ready after your first voice note."
   If data: 
   - Cover page: contact name, year, notes count
   - Stats: "[N] voice notes · [X] hours · [streak] day best streak"
   - Sample pages: first 3 entries as transcript cards
   - Preview state: "Full book available after 90 days" if streak < 90

3. Anniversary detection in DiaryStore.diaryAnniversaries:
   Check if first entry was 365 days ago.
   In home_screen.dart on open: if anniversary today → golden banner:
   "🎂 1 year with [Name] · Your Memory Book is ready."
   Tap → MemoryBookScreen with diaryId.

4. Add to diary_thread_screen.dart _MoreMenuSheet:
   "📖 Memory Book" option.
   If streak < 30: show "Preview · unlocks at 30 days" (disabled).
   If streak >= 30: enabled → MemoryBookScreen with diaryId.

5. In memory_book_screen.dart add two stub buttons (greyed):
   "Download PDF (coming soon)"
   "Print a copy (coming soon)"
   These signal the product vision. Will activate with backend.
```

---

## PHASE 6 — Experimental & Vision (P3)

---

### Prompt 31 — Voice Mood Intelligence (Phase 1)

```
Implement Phase 1 of voice mood intelligence — amplitude-based tinting.

1. Create lib/frontend/services/audio_analysis_service.dart:
   class AudioAnalysisResult { averageAmplitude, peakAmplitude, pace,
   energy (derived), warmth (derived) }
   
   class AudioAnalysisService {
     static Future<AudioAnalysisResult?> analyse(String audioPath) async {
       // STUB: return AudioAnalysisResult(0.5, 0.7, 0.5)
       // TODO: Implement with audioplayers amplitude + RMS calculation
       return null;
     }
   }

2. In DiaryEntry: moodEnergy: double? (from Prompt 2 ✓)
   DiaryStore.updateEntryMood(String entryId, double energy) ✓

3. In diary_thread_screen.dart _VoiceBubble:
   moodEnergy → colour tint (Stack with Positioned.fill at low alpha):
   <= 0.3: Color(0xFF0A5AC2) at 0.03 alpha (cool)
   <= 0.6: transparent (neutral)
   <= 0.8: Color(0xFFFF9500) at 0.04 alpha (warm)
   > 0.8: Color(0xFFFF6B00) at 0.06 alpha (energetic)

4. After playback completes: if entry.moodEnergy == null:
   AudioAnalysisService.analyse(entry.path).then((r) {
     if (r != null) DiaryStore.instance.updateEntryMood(entry.id, r.energy);
   });
   Tint appears on second playback. Intentional.

5. In memory_tree_screen.dart _TreePainter:
   Tree nodes get subtle colour variation based on that month's 
   average moodEnergy: high → more amber, low → cooler hue.
```

---

### Prompt 32 — Home Screen Widget Foundation

```
Implement home screen widget infrastructure.

Add to pubspec.yaml: home_widget: ^0.7.0

1. Create lib/frontend/services/home_widget_service.dart:
   HomeWidgetService.update() → async:
   Reads DiaryStore most recent diary + PulseStore received status + streak.
   Saves via HomeWidget.saveWidgetData():
   - 'contact_name', 'streak_days', 'pulse_time', 'was_here', 'last_updated'
   Calls HomeWidget.updateWidget(name: 'SaanjhWidget', androidName: ..., iOSName: ...)
   
   Call update() from: HomeScreen.initState(), PulseStore listener, 
   DiaryStore listener.

2. Android widget:
   Create android/app/src/main/res/layout/saanjh_widget.xml:
   Dark amber-tinted 2×2 and 2×4 layouts with contact name, pulse time,
   streak count. See home_widget package docs for RemoteViews setup.
   
   Create android/app/src/main/kotlin/.../SaanjhWidgetProvider.kt:
   AppWidgetProvider reading saved HomeWidget data.
   Register in AndroidManifest.xml.
   Create res/xml/saanjh_widget_info.xml.

3. iOS widget:
   Create ios/SaanjhWidget/ Swift Extension target.
   Small (2×2): "[Name] • 🔥 N"
   Medium (2×4): "[Name] was here at [time] • 🔥 N • Record →"
   Reads from UserDefaults via App Groups.

4. Document clearly: "iOS requires App Group in Apple Developer Portal. 
   Android requires manifest registration. Both require native builds."
```

---

### Prompt 33 — Story Card Export (Share a Voice Moment)

```
Implement story card export — share voice notes as beautiful visual cards.

Requires share_plus and path_provider (added in Prompt 21 ✓).

1. Create lib/frontend/widgets/voice_share_card.dart:
   Off-screen rendered 400×400 RepaintBoundary widget:
   - Background: ember gradient (same as app)
   - "[Name]'s voice" serifItalic(18) textMuted top
   - Static waveform bars centred (140px height, seed-based same as bubbles)
   - Duration "0:18" in display(28) amber
   - "[Month] [Day], [Year]" label(13) textFaint
   - "Saanjh · saanjh.app" small watermark bottom

2. In ShareCardService (Prompt 21): add shareVoiceCard():
   Captures VoiceShareCard → temp file → Share.shareXFiles()
   Text: "A moment from [contactName] on Saanjh 🎙 · saanjh.app"

3. In diary_thread_screen.dart _VoiceBubbleContextSheet (Prompt 19):
   "Share this moment →" now works:
   Show VoiceShareCard via Offstage.
   Call ShareCardService.shareVoiceCard(cardKey, contact.displayName).
   Show small CircularProgressIndicator while capturing.

4. In memory_jar_screen.dart: long-press → "Share →" works same way.

5. No aggressive CTAs on the shared card. Just "saanjh.app" watermark.
   Curiosity about what Saanjh is → conversion mechanism.
```

---

### Prompt 34 — Final Cleanup, Consistency Pass & Bug Sweep

```
Final cleanup, consistency pass, and bug sweep across the entire app.

1. Import audit — every screen file:
   - Remove unused imports
   - Ensure all services/stores from Prompts 1–33 are properly imported
   - Check for circular imports
   - Verify all new screens are in app_router.dart with proper routes

2. Compile and fix all warnings:
   - No unnecessary non-null assertions
   - No unused variables
   - No deprecated API calls
   - No missing required parameters
   - All switch statements exhaustive

3. Spacing consistency — replace hardcoded values with AppSpacing in:
   diary_thread_screen.dart, pulse_screen.dart, home_screen.dart, me_screen.dart

4. Typography consistency — audit serifItalic usage:
   Max 2 instances per screen. Where overused → replace with body().

5. SaanjhAvatar deduplication (from Prompt 23):
   Verify SaanjhAvatar is used everywhere. Remove old avatar+ring code.

6. SaanjhSheet standardization (from Prompt 23):
   Every showModalBottomSheet: isScrollControlled: true, 
   backgroundColor: Colors.transparent, content in SaanjhSheet.

7. Verify all navigation flows:
   New user: Splash → Film → Phone → OTP → Name → ConnectFirst → Home ✓
   Invited: Deep-link → InviteAccept → Phone → OTP → Name → Diary ✓
   Daily: Home → Diary → Record → Send → Receipt ✓
   Pulse: Home → Pulse tab → Hold → Send sheet → Ritual → Sent ✓
   Milestone: Send → Home → Milestone screen ✓
   On This Day: Open app → Banner → Inline play ✓
   Morning: Open before 9AM → Morning overlay → Continue ✓
   Streak break: Miss day → Card state → Banner in thread ✓

8. Performance check:
   - No AnimationControllers leaked (all disposed ✓)
   - No ListenableBuilders rebuilding unnecessarily
   - No setState inside build()
   - All heavy computations outside build()

9. Final memory save in user memory system noting all 34 prompts complete.
```

---

## Summary Reference Table

| # | Prompt | Phase | Priority | Key Files |
|---|---|---|---|---|
| 1 | Universal Model | Foundation | P0 | All screens, app_router |
| 2 | Data Layer | Foundation | P0 | diary_store.dart |
| 3 | Cleanup | Foundation | P0 | All screens |
| 4 | Emotional Film | Onboarding | P0 | onboarding_film_screen |
| 5 | Universal Connect | Onboarding | P0 | connect_first_screen, invite_screen |
| 6 | Listener's Receipt | Activation | P0 | diary_thread, notification_banner |
| 7 | Prompt Cards | Activation | P0 | diary_thread, record_screen |
| 8 | Streak Break | Activation | P0 | diary_store, diary_thread, home |
| 9 | Milestones | Emotional Core | P1 | streak_milestone_screen |
| 10 | On This Day | Emotional Core | P1 | on_this_day_service, home |
| 11 | Morning Ritual | Emotional Core | P1 | morning_service, morning_overlay |
| 12 | Pulse Ritual | Emotional Core | P1 | pulse_screen |
| 13 | Memory Jar | Emotional Core | P1 | diary_thread, me_screen, memory_jar |
| 14 | Occasions | Emotional Core | P1 | occasion_service, home |
| 15 | Weather | Emotional Core | P1 | diary_store, home, diary_thread |
| 16 | Nav Restructure | Emotional Core | P1 | home_screen |
| 17 | Memory Tree | Emotional Core | P1 | memory_tree_screen |
| 18 | Empty States | Polish | P1 | All screens |
| 19 | Voice Bubbles | Polish | P1 | diary_thread |
| 20 | Profile | Polish | P1 | me_screen, diary_thread, discover |
| 21 | Milestone Cards | Growth | P1-P2 | milestone_share_card, share_card_service |
| 22 | Transcription | Growth | P2 | transcription_service, record_screen |
| 23 | Design System | System | P2 | saanjh_avatar, saanjh_sheet, saanjh_badge |
| 24 | Loading States | System | P2 | saanjh_shimmer, all screens |
| 25 | Accessibility | System | P2 | All screens |
| 26 | Reactions | Features | P2 | diary_entry, memory_tree |
| 27 | Journal | Features | P2 | personal_reflection_store, me_screen |
| 28 | Group Diaries | Features | P2 | group_thread_screen |
| 29 | Notifications | Features | P2 | notification_service |
| 30 | Memory Book | Features | P2 | memory_book_generator, memory_book |
| 31 | Mood Intelligence | Vision | P3 | audio_analysis_service |
| 32 | Home Widget | Vision | P3 | home_widget_service, Android/iOS |
| 33 | Story Cards | Vision | P3 | voice_share_card |
| 34 | Final Cleanup | All | All | All files |

---

**Total: 34 Prompts · 65+ Items · Complete Coverage**

*Copy each numbered prompt exactly as written. Implement one, then paste the next.*
