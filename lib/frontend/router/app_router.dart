import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/connect_first/connect_first_screen.dart';
import '../screens/pre_commit/pre_commit_screen.dart';
import '../screens/create_group/create_group_screen.dart';
import '../screens/invite_accept/invite_accept_screen.dart';
import '../screens/onboarding_film/onboarding_film_screen.dart';
import '../screens/discover/discover_screen.dart';
import '../screens/memory_book/memory_book_screen.dart';
import '../screens/onboarding_intro/onboarding_intro_screen.dart';
import '../screens/flicker/flicker_screen.dart';
import '../screens/wish/wish_screen.dart';
import '../screens/diary_thread/diary_thread_screen.dart';
import '../screens/family/family_screen.dart';
import '../screens/first_send/first_send_screen.dart';
import '../screens/group_thread/group_thread_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/invite_recipient/invite_recipient_screen.dart';
import '../screens/memory_detail/memory_detail_screen.dart';
import '../screens/memory_tree/memory_tree_screen.dart';
import '../screens/name_entry/name_entry_screen.dart';
import '../screens/occasion_plan/occasion_plan_screen.dart';
import '../screens/otp_verify/otp_verify_screen.dart';
import '../screens/parent_invite_entry/parent_invite_entry_screen.dart' show InviteScreen;
import '../screens/phone_number/phone_number_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/relationship_select/relationship_select_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/memory_jar/memory_jar_screen.dart';
import '../screens/people/people_screen.dart';
import '../screens/personal_journal/personal_journal_screen.dart';
import '../screens/on_this_day/on_this_day_screen.dart';
import '../screens/anniversary/anniversary_screen.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/record/record_screen.dart';
import '../screens/streak_milestone/streak_milestone_screen.dart';
import '../screens/welcome_home/welcome_home_screen.dart';
import '../screens/me/me_screen.dart';
import '../state/user_store.dart';
import 'app_routes.dart';

// All routes accessible WITHOUT being logged in.
// Includes the full pre-login onboarding flow.
const _publicRoutes = {
  AppRoutes.splash,
  AppRoutes.onboardingFilm,
  AppRoutes.onboardingIntro,
  AppRoutes.preCommit,           // onboarding step
  AppRoutes.relationshipSelect,  // onboarding step
  AppRoutes.phoneNumber,
  AppRoutes.otpVerify,
  AppRoutes.nameEntry,           // post-OTP onboarding (user just logged in)
  AppRoutes.inviteRecipient,     // deep-link accessible before login
  AppRoutes.inviteAccept,        // deep-link accessible before login
  AppRoutes.welcomeHome,         // first-time welcome
  AppRoutes.connectFirst,        // shown when no connection yet
};

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    redirect: _redirect,
    routes: [
      GoRoute(
        path: AppRoutes.onboardingFilm,
        name: 'film',
        pageBuilder: (_, s) =>
            const NoTransitionPage(child: OnboardingFilmScreen()),
      ),
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        pageBuilder: (_, s) => const NoTransitionPage(child: SplashScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingIntro,
        name: 'intro',
        pageBuilder: (_, s) =>
            const MaterialPage(child: OnboardingIntroScreen()),
      ),
      GoRoute(
        path: AppRoutes.preCommit,
        name: 'preCommit',
        pageBuilder: (_, s) =>
            const MaterialPage(child: PreCommitScreen()),
      ),
      GoRoute(
        path: AppRoutes.relationshipSelect,
        name: 'relationshipSelect',
        pageBuilder: (_, s) =>
            const MaterialPage(child: RelationshipSelectScreen()),
      ),
      GoRoute(
        path: AppRoutes.phoneNumber,
        name: 'phone',
        pageBuilder: (_, s) =>
            const MaterialPage(child: PhoneNumberScreen()),
      ),
      GoRoute(
        path: AppRoutes.otpVerify,
        name: 'otp',
        pageBuilder: (_, s) =>
            const MaterialPage(child: OtpVerifyScreen()),
      ),
      GoRoute(
        path: AppRoutes.nameEntry,
        name: 'name',
        pageBuilder: (_, s) =>
            const MaterialPage(child: NameEntryScreen()),
      ),
      GoRoute(
        path: AppRoutes.inviteRecipient,
        name: 'inviteRecipient',
        pageBuilder: (_, s) =>
            const MaterialPage(child: InviteRecipientScreen()),
      ),
      GoRoute(
        path: AppRoutes.welcomeHome,
        name: 'welcome',
        pageBuilder: (_, s) =>
            const MaterialPage(child: WelcomeHomeScreen()),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        pageBuilder: (_, s) => const NoTransitionPage(child: HomeScreen()),
      ),
      GoRoute(
        path: AppRoutes.connectFirst,
        name: 'connectFirst',
        pageBuilder: (_, s) =>
            const MaterialPage(child: ConnectFirstScreen()),
      ),
      GoRoute(
        path: AppRoutes.invite,
        name: 'invite',
        pageBuilder: (_, s) => const MaterialPage(child: InviteScreen()),
      ),
      GoRoute(
        path: AppRoutes.inviteAccept,
        name: 'inviteAccept',
        pageBuilder: (_, s) {
          final extra = s.extra as Map<String, dynamic>? ?? {};
          return MaterialPage(child: InviteAcceptScreen(
            inviterName: extra['inviterName'] as String? ?? '',
          ));
        },
      ),
      GoRoute(
        path: AppRoutes.createGroup,
        name: 'createGroup',
        pageBuilder: (_, s) =>
            const MaterialPage(child: CreateGroupScreen()),
      ),
      GoRoute(
        path: AppRoutes.memoryTree,
        name: 'memoryTree',
        pageBuilder: (_, s) =>
            const MaterialPage(child: MemoryTreeScreen()),
      ),
      GoRoute(
        path: AppRoutes.diaryThread,
        name: 'diaryThread',
        pageBuilder: (_, s) {
          final extra = s.extra as Map<String, dynamic>? ?? {};
          return MaterialPage(child: DiaryThreadScreen(
            diaryId: extra['diaryId'] as String? ?? '',
          ));
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        pageBuilder: (_, s) => const MaterialPage(child: SettingsScreen()),
      ),
      GoRoute(
        path: AppRoutes.voiceRecord,
        name: 'record',
        pageBuilder: (_, s) => const MaterialPage(child: RecordScreen()),
      ),
      GoRoute(
        path: AppRoutes.family,
        name: 'family',
        pageBuilder: (_, s) => const MaterialPage(child: FamilyScreen()),
      ),
      GoRoute(
        path: AppRoutes.memoryDetail,
        name: 'memoryDetail',
        pageBuilder: (_, s) =>
            const MaterialPage(child: MemoryDetailScreen()),
      ),
      GoRoute(
        path: AppRoutes.occasionPlan,
        name: 'occasion',
        pageBuilder: (_, s) =>
            const MaterialPage(child: OccasionPlanScreen()),
      ),
      GoRoute(
        path: AppRoutes.profile,
        name: 'profile',
        pageBuilder: (_, s) => const MaterialPage(child: ProfileScreen()),
      ),
      GoRoute(
        path: AppRoutes.groupThread,
        name: 'groupThread',
        pageBuilder: (_, s) {
          final extra = s.extra as Map<String, dynamic>? ?? {};
          return MaterialPage(child: GroupThreadScreen(
            diaryId: extra['diaryId'] as String?,
          ));
        },
      ),
      GoRoute(
        path: AppRoutes.firstSend,
        name: 'firstSend',
        pageBuilder: (_, s) =>
            const MaterialPage(child: FirstSendScreen()),
      ),
      GoRoute(
        path: AppRoutes.discover,
        name: 'discover',
        pageBuilder: (_, s) => const MaterialPage(child: DiscoverScreen()),
      ),
      GoRoute(
        path: AppRoutes.memoryBook,
        name: 'memoryBook',
        pageBuilder: (_, s) =>
            const MaterialPage(child: MemoryBookScreen()),
      ),
      GoRoute(
        path: AppRoutes.wish,
        name: 'wish',
        pageBuilder: (_, s) => const MaterialPage(child: WishScreen()),
      ),
      GoRoute(
        path: AppRoutes.flicker,
        name: 'flicker',
        pageBuilder: (_, s) =>
            const MaterialPage(child: FlickerScreen()),
      ),
      GoRoute(
        path: AppRoutes.streakMilestone,
        name: 'streak',
        pageBuilder: (_, s) =>
            const MaterialPage(child: StreakMilestoneScreen()),
      ),
      GoRoute(
        path: AppRoutes.anniversary,
        name: 'anniversary',
        pageBuilder: (_, s) =>
            const MaterialPage(child: AnniversaryScreen()),
      ),
      GoRoute(
        path: AppRoutes.onThisDay,
        name: 'onThisDay',
        pageBuilder: (_, s) =>
            const MaterialPage(child: OnThisDayScreen()),
      ),
      GoRoute(
        path: AppRoutes.memoryJar,
        name: 'memoryJar',
        pageBuilder: (_, s) =>
            const MaterialPage(child: MemoryJarScreen()),
      ),
      GoRoute(
        path: AppRoutes.people,
        name: 'people',
        pageBuilder: (_, s) => const MaterialPage(child: PeopleScreen()),
      ),
      GoRoute(
        path: AppRoutes.personalJournal,
        name: 'journal',
        pageBuilder: (_, s) =>
            const MaterialPage(child: PersonalJournalScreen()),
      ),
      GoRoute(
        path: '/me',
        name: 'me',
        pageBuilder: (_, s) => const MaterialPage(child: MeScreen()),
      ),
    ],
  );
}

// Extracted as a top-level function so GoRouter doesn't recreate it on rebuild.
// Reads SharedPreferences ONCE on first call and caches the result.
bool? _hasSeenFilm;

Future<String?> _redirect(BuildContext context, GoRouterState state) async {
  final path = state.fullPath ?? AppRoutes.splash;

  // First-launch check — only runs once (cached after first read)
  if (path == AppRoutes.splash) {
    _hasSeenFilm ??= (await SharedPreferences.getInstance())
        .getBool('has_seen_film') ?? false;
    if (!_hasSeenFilm!) return AppRoutes.onboardingFilm;
  }

  final isLoggedIn = UserStore.instance.isLoggedIn;
  final isPublic   = _publicRoutes.contains(path);

  // Not logged in trying to reach a private route → send to onboarding start
  if (!isLoggedIn && !isPublic) return AppRoutes.onboardingIntro;

  // Already logged in and fully onboarded → skip auth screens
  if (isLoggedIn &&
      UserStore.instance.isOnboarded &&
      (path == AppRoutes.phoneNumber || path == AppRoutes.otpVerify)) {
    return AppRoutes.home;
  }

  return null;
}
