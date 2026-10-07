import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';

/// 底部导航框架。
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(countsProvider).value?.total ?? 0;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: '视频',
          ),
          const NavigationDestination(
            icon: Icon(Icons.photo_outlined),
            selectedIcon: Icon(Icons.photo),
            label: '图片',
          ),
          const NavigationDestination(
            icon: Icon(Icons.subscriptions_outlined),
            selectedIcon: Icon(Icons.subscriptions),
            label: '关注',
          ),
          const NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: '论坛',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.person_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.person),
            ),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
