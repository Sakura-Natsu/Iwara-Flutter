import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models/image.dart';
import 'models/social.dart';
import 'models/video.dart';
import 'pages/auth/login_page.dart';
import 'pages/downloads/downloads_page.dart';
import 'pages/downloads/local_player_page.dart';
import 'pages/forum/forum_page.dart';
import 'pages/forum/forum_section_page.dart';
import 'pages/forum/forum_thread_page.dart';
import 'pages/home/home_shell.dart';
import 'pages/images/image_detail_page.dart';
import 'pages/images/images_page.dart';
import 'pages/library/favorites_page.dart';
import 'pages/library/history_page.dart';
import 'pages/me/me_page.dart';
import 'pages/messages/chat_page.dart';
import 'pages/messages/conversations_page.dart';
import 'pages/messages/friends_page.dart';
import 'pages/messages/notifications_page.dart';
import 'pages/playlist/playlist_page.dart';
import 'pages/playlist/user_playlists_page.dart';
import 'pages/posts/post_page.dart';
import 'pages/search/search_page.dart';
import 'pages/settings/settings_page.dart';
import 'pages/subscriptions/subscriptions_page.dart';
import 'pages/user/follow_list_page.dart';
import 'pages/user/profile_page.dart';
import 'pages/videos/video_detail_page.dart';
import 'pages/videos/videos_page.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/videos',
    // 兼容官网链接：/video/:id/:slug、/forum/:section/:id/:slug 等
    redirect: (context, state) {
      final seg = state.uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (seg.isEmpty) return '/videos';
      const single = {'video', 'image', 'profile', 'playlist', 'post'};
      if (seg.length > 2 && single.contains(seg[0])) {
        return '/${seg[0]}/${seg[1]}';
      }
      if (seg.length > 3 && seg[0] == 'forum') {
        return '/forum/${seg[1]}/${seg[2]}';
      }
      return null;
    },
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('页面不存在')),
      body: Center(
        child: FilledButton(
          onPressed: () => context.go('/videos'),
          child: const Text('返回首页'),
        ),
      ),
    ),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/videos', builder: (_, _) => const VideosPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/images', builder: (_, _) => const ImagesPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/subscriptions',
                builder: (_, _) => const SubscriptionsPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/forum', builder: (_, _) => const ForumPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/me', builder: (_, _) => const MePage()),
          ]),
        ],
      ),
      GoRoute(
        path: '/video/:id',
        builder: (_, s) => VideoDetailPage(
          id: s.pathParameters['id']!,
          initial: s.extra is Video ? s.extra as Video : null,
        ),
      ),
      GoRoute(
        path: '/image/:id',
        builder: (_, s) => ImageDetailPage(
          id: s.pathParameters['id']!,
          initial: s.extra is GalleryImage ? s.extra as GalleryImage : null,
        ),
      ),
      GoRoute(
        path: '/profile/:username',
        builder: (_, s) =>
            ProfilePage(username: s.pathParameters['username']!),
      ),
      GoRoute(
        path: '/user/:userId/follows',
        builder: (_, s) => FollowListPage(
          userId: s.pathParameters['userId']!,
          name: s.uri.queryParameters['name'],
          showFollowing: s.uri.queryParameters['tab'] == 'following',
        ),
      ),
      GoRoute(
        path: '/user/:userId/playlists',
        builder: (_, s) => UserPlaylistsPage(
          userId: s.pathParameters['userId']!,
          name: s.uri.queryParameters['name'],
        ),
      ),
      GoRoute(
        path: '/playlist/:id',
        builder: (_, s) => PlaylistPage(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/search',
        builder: (_, s) => SearchPage(
          initialQuery: s.uri.queryParameters['q'],
          initialType: s.uri.queryParameters['type'],
        ),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(path: '/favorites', builder: (_, _) => const FavoritesPage()),
      GoRoute(path: '/history', builder: (_, _) => const HistoryPage()),
      GoRoute(path: '/downloads', builder: (_, _) => const DownloadsPage()),
      GoRoute(
        path: '/local-video',
        builder: (_, s) => LocalPlayerPage(
          path: s.uri.queryParameters['path']!,
          title: s.uri.queryParameters['title'] ?? '',
          videoId: s.uri.queryParameters['id'],
        ),
      ),
      GoRoute(
          path: '/notifications',
          builder: (_, _) => const NotificationsPage()),
      GoRoute(
          path: '/messages', builder: (_, _) => const ConversationsPage()),
      GoRoute(
        path: '/messages/:id',
        builder: (_, s) => ChatPage(
          conversationId: s.pathParameters['id']!,
          initial: s.extra is Conversation ? s.extra as Conversation : null,
        ),
      ),
      GoRoute(path: '/friends', builder: (_, _) => const FriendsPage()),
      GoRoute(
        path: '/forum/:section',
        builder: (_, s) =>
            ForumSectionPage(section: s.pathParameters['section']!),
      ),
      GoRoute(
        path: '/forum/:section/:threadId',
        builder: (_, s) => ForumThreadPage(
          section: s.pathParameters['section']!,
          threadId: s.pathParameters['threadId']!,
        ),
      ),
      GoRoute(
        path: '/post/:id',
        builder: (_, s) => PostPage(id: s.pathParameters['id']!),
      ),
    ],
  );
});
