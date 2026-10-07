import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../../widgets/net_image.dart';
import '../../widgets/states.dart';

class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final me = auth.value;
    final counts = ref.watch(countsProvider).value;
    final theme = Theme.of(context);

    Widget entry(IconData icon, String title, String route,
            {int badge = 0, bool needLogin = false}) =>
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (badge > 0) Badge(label: Text('$badge')),
            const Icon(Icons.chevron_right),
          ]),
          onTap: () {
            if (needLogin && me == null) {
              context.push('/login');
            } else {
              context.push(route);
            }
          },
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(authProvider.notifier).reload();
          ref.invalidate(countsProvider);
        },
        child: ListView(
          children: [
            // 账号卡片
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                margin: EdgeInsets.zero,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: me == null
                      ? () => context.push('/login')
                      : () => context.push('/profile/${me.user.username}'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      UserAvatar(me?.user, size: 56),
                      const SizedBox(width: 16),
                      Expanded(
                        child: auth.isLoading && me == null
                            ? const Text('加载中…')
                            : me == null
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('点击登录',
                                          style: theme.textTheme.titleMedium),
                                      const SizedBox(height: 4),
                                      Text(
                                        auth.hasError
                                            ? '加载账号失败，下拉重试'
                                            : '登录后可收藏、评论、关注作者',
                                        style: TextStyle(color: theme.hintColor),
                                      ),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Flexible(
                                          child: Text(me.user.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  theme.textTheme.titleMedium),
                                        ),
                                        if (me.user.premium) ...[
                                          const SizedBox(width: 6),
                                          const Icon(Icons.workspace_premium,
                                              size: 18, color: Colors.amber),
                                        ],
                                      ]),
                                      const SizedBox(height: 2),
                                      Text('@${me.user.username}',
                                          style:
                                              TextStyle(color: theme.hintColor)),
                                    ],
                                  ),
                      ),
                      const Icon(Icons.chevron_right),
                    ]),
                  ),
                ),
              ),
            ),
            if (me != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  _QuickEntry(
                    icon: Icons.notifications_outlined,
                    label: '通知',
                    badge: counts?.notifications ?? 0,
                    onTap: () => context.push('/notifications'),
                  ),
                  _QuickEntry(
                    icon: Icons.mail_outline,
                    label: '私信',
                    badge: counts?.messages ?? 0,
                    onTap: () => context.push('/messages'),
                  ),
                  _QuickEntry(
                    icon: Icons.people_outline,
                    label: '好友',
                    badge: counts?.friendRequests ?? 0,
                    onTap: () => context.push('/friends'),
                  ),
                  _QuickEntry(
                    icon: Icons.person_add_alt_outlined,
                    label: '关注',
                    onTap: () => context.push(
                        '/user/${me.user.id}/follows?tab=following&name=${Uri.encodeComponent(me.user.name)}'),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            entry(Icons.favorite_border, '我的收藏', '/favorites', needLogin: true),
            if (me != null)
              entry(Icons.playlist_play, '我的播放列表',
                  '/user/${me.user.id}/playlists?name=${Uri.encodeComponent(me.user.name)}'),
            entry(Icons.history, '观看历史', '/history', needLogin: true),
            entry(Icons.download_outlined, '离线下载', '/downloads'),
            const Divider(),
            entry(Icons.settings_outlined, '设置', '/settings'),
            if (me != null)
              ListTile(
                leading: Icon(Icons.logout, color: theme.colorScheme.error),
                title: Text('退出登录',
                    style: TextStyle(color: theme.colorScheme.error)),
                onTap: () async {
                  if (await confirm(context, '确定退出登录？', okText: '退出')) {
                    await ref.read(authProvider.notifier).logout();
                    ref.invalidate(countsProvider);
                  }
                },
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _QuickEntry extends StatelessWidget {
  const _QuickEntry({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge'),
                child: Icon(icon, size: 26),
              ),
              const SizedBox(height: 6),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ]),
          ),
        ),
      );
}
