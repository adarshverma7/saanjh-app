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
import '../state/user_store.dart';
import 'app_routes.dart';

// Routes that don't require auth
const _publicRoutes = {
  AppRoutes.splash,
  AppRoutes.onboardingFilm,
  AppRoutes.onboardingIntro,
  AppRoutes.phoneNumber,
  AppRoutes.otpVerify,
};

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    redirect: (context, state) async {
      final path = state.fullPath ?? AppRoutes.splash;

      // On first launch only, show the onboarding film
      if (path == AppRoutes.splash) {
        final prefs = await SharedPreferences.getInstance();
        final hasSeen = prefs.getBool('has_seen_film') ?? false;
        if (!hasSeen) return AppRoutes.onboardingFilm;
      }

      final isLoggedIn = UserStore.instance.isLoggedIn;
      final isPublic   = _publicRoutes.contains(path);

      // Not logged in trying to reach a private route → send to onboarding
      if (!isLoggedIn && !isPublic) return AppRoutes.onboardingIntro;

      // Logged in but landing on a public auth screen → send home
      if (isLoggedIn && (path == AppRoutes.phoneNumber || path == AppRoutes.otpVerify)) {
        return AppRoutes.home;
      }

      return null;
    },
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
        name: 'nameEntry',
        pageBuilder: (_, s) =>
            const MaterialPage(child: NameEntryScreen()),
      ),
      GoRoute(
        path: AppRoutes.inviteRecipient,
        name: 'inviteRecipient',
        pageBuilder: (_, s) {
          final extra = s.extra as Map<String, String>?;
          return MaterialPage(
            child: InviteRecipientScreen(
              prefillName: extra?['name'],
              prefillPhone: extra?['phone'],
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.welcomeHome,
        name: 'welcome',
        pageBuilder: (_, s) =>
            const MaterialPage(child: WelcomeHomeScreen()),
      ),
      GoRoute(
        path: AppRoutes.connectFirst,
        name: 'connectFirst',
        pageBuilder: (_, s) =>
            const MaterialPage(child: ConnectFirstScreen()),
      ),
      GoRoute(
        path: AppRoutes.inviteAccept,
        name: 'inviteAccept',
        pageBuilder: (_, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return MaterialPage(
            child: InviteAcceptScreen(
              inviterName:
                  extra?['inviterName'] as String? ?? 'Someone special',
              inviterId: extra?['inviterId'] as String? ?? '',
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        pageBuilder: (_, s) => const NoTransitionPage(child: HomeScreen()),
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
        pageBuilder: (_, s) {
          final extra = s.extra as Map<String, dynamic>?;
          final diaryId = extra?['diaryId'] as String?;
          return MaterialPage(child: MemoryTreeScreen(diaryId: diaryId));
        },
      ),
      GoRoute(
        path: AppRoutes.diaryThread,
        name: 'diaryThread',
        pageBuilder: (_, s) {
          final extra = s.extra as Map<String, dynamic>?;
          final diaryId = extra?['diaryId'] as String? ?? '';
          return MaterialPage(child: DiaryThreadScreen(diaryId: diaryId));
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        pageBuilder: (_, s) =>
            const MaterialPage(child: SettingsScreen()),
      ),
      GoRoute(
        path: AppRoutes.voiceRecord,
        name: 'record',
        pageBuilder: (_, s) {
          final extra = s.extra as Map<String, dynamic>?;
          final isVideo = extra?['isVideo'] as bool? ?? false;
          final autoStart = extra?['autoStart'] as bool? ?? false;
          final broadcastTo =
              (extra?['broadcastTo'] as List?)?.cast<String>();
          final broadcastNames =
              (extra?['broadcastNames'] as List?)?.cast<String>();
          final prompt = extra?['prompt'] as String?;
          final isPrivateReflection =
              extra?['isPrivateReflection'] as bool? ?? false;
          final occasionTag = extra?['occasionTag'] as String?;
          final targetDiaryId = extra?['targetDiaryId'] as String?;
          final parentEntryId = extra?['parentEntryId'] as String?;
          final reactionContext = extra?['reactionContext'] as String?;
          return MaterialPage(
            child: RecordScreen(
              isVideo: isVideo,
              autoStart: autoStart,
              broadcastTo: broadcastTo,
              broadcastNames: broadcastNames,
              prompt: prompt,
              isPrivateReflection: isPrivateReflection,
              occasionTag: occasionTag,
              targetDiaryId: targetDiaryId,
              parentEntryId: parentEntryId,
              reactionContext: reactionContext,
            ),
          );
        },
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
        path: AppRoutes.invite,
        name: 'inviteSender',
        pageBuilder: (_, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return MaterialPage(
            child: InviteScreen(
              prefillName: extra?['name'] as String?,
              prefillPhone: extra?['phone'] as String?,
              isParentInvite: extra?['isParentInvite'] as bool? ?? false,
            ),
          );
        },
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
        pageBuilder: (_, s) =>
            const MaterialPage(child: ProfileScreen()),
      ),
      GoRoute(
        path: AppRoutes.groupThread,
        name: 'groupThread',
        pageBuilder: (_, s) {
          final extra = s.extra as Map<String, dynamic>?;
          final diaryId = extra?['diaryId'] as String?;
          return MaterialPage(child: GroupThreadScreen(diaryId: diaryId));
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
        pageBuilder: (_, s) =>
            const MaterialPage(child: DiscoverScreen()),
      ),
      GoRoute(
        path: AppRoutes.memoryBook,
        name: 'memoryBook',
        pageBuilder: (_, s) {
          final extra = s.extra as Map<String, dynamic>?;
          final diaryId = extra?['diaryId'] as String?;
          final isGift = extra?['isGift'] as bool? ?? false;
          return MaterialPage(
              child: MemoryBookScreen(diaryId: diaryId, isGift: isGift));
        },
      ),
      GoRoute(
        path: AppRoutes.flicker,
        name: 'flicker',
        pageBuilder: (_, s) {
          final extra = s.extra as Map<String, dynamic>?;
          final targetId = extra?['targetDiaryId'] as String?;
          return MaterialPage(child: FlickerScreen(targetDiaryId: targetId));
        },
      ),
      GoRoute(
        path: AppRoutes.wish,
        name: 'wish',
        pageBuilder: (_, s) {
          final extra = s.extra as Map<String, dynamic>?;
          final name = extra?['name'] as String? ?? 'them';
          return MaterialPage(child: WishScreen(recipientName: name));
        },
      ),
      GoRoute(
        path: AppRoutes.anniversary,
        name: 'anniversary',
        pageBuilder: (_, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return MaterialPage(
            child: AnniversaryScreen(
              diaryId:     extra?['diaryId']     as String? ?? '',
              contactName: extra?['contactName'] as String? ?? '',
              years:       extra?['years']       as int?    ?? 1,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.streakMilestone,
        name: 'streakMilestone',
        pageBuilder: (_, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return MaterialPage(
            child: StreakMilestoneScreen(
              diaryId: extra?['diaryId'] as String? ?? '',
              contactName: extra?['contactName'] as String? ?? '',
              milestone: extra?['milestone'] as int? ?? 0,
            ),
          );
        },
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
        pageBuilder: (_, s) =>
            const MaterialPage(child: PeopleScreen()),
      ),
      GoRoute(
        path: AppRoutes.personalJournal,
        name: 'personalJournal',
        pageBuilder: (_, s) =>
            const MaterialPage(child: PersonalJournalScreen()),
      ),
    ],
  );
}
