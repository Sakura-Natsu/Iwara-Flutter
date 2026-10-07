import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../models/social.dart';
import '../../models/user.dart';
import '../../providers.dart';
import '../../widgets/net_image.dart';
import '../../widgets/paging.dart';
import '../../widgets/states.dart';
import 'common.dart';

/// 通知列表。
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    if (me == null) {
      return const LoginRequiredScaffold(
        title: '通知',
        text: '登录后查看通知',
        icon: Icons.notifications_none,
      );
    }
    return _NotificationsView(key: ValueKey(me.user.id), me: me.user);
  }
}

class _NotificationsView extends ConsumerStatefulWidget {
  const _NotificationsView({super.key, required this.me});

  final User me;

  @override
  ConsumerState<_NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends ConsumerState<_NotificationsView> {
  late final PagingController<IwaraNotification> controller = PagingController(
    (page) => ref.read(apiProvider).notifications(widget.me.id, page: page),
    dedupeKey: (n) => n.id,
  );

  bool _markingAll = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// 乐观标记已读，失败回滚。
  Future<void> _markRead(IwaraNotification n) async {
    controller.updateWhere((e) => e.id == n.id, (e) => e.markRead());
    try {
      await ref.read(apiProvider).markNotificationRead(n.id);
      if (mounted) ref.invalidate(countsProvider);
    } catch (e) {
      controller.updateWhere((x) => x.id == n.id, (_) => n);
      if (mounted) showError(context, e);
    }
  }

  Future<void> _markAll() async {
    final unread = controller.items.where((n) => !n.read).toList();
    if (unread.isEmpty) return;
    setState(() => _markingAll = true);
    final api = ref.read(apiProvider);
    var failed = 0;
    for (final n in unread) {
      try {
        await api.markNotificationRead(n.id);
        controller.updateWhere((e) => e.id == n.id, (e) => e.markRead());
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _markingAll = false);
    ref.invalidate(countsProvider);
    showToast(context, failed == 0 ? '已全部标记为已读' : '有 $failed 条通知标记失败');
  }

  void _open(IwaraNotification n) {
    if (!n.read) _markRead(n);
    final route = _routeFor(n);
    if (route != null) context.push(route);
  }

  String? _routeFor(IwaraNotification n) {
    if (n.video != null) return '/video/${n.video!.id}';
    if (n.image != null) return '/image/${n.image!.id}';
    final profile = n.profileUser;
    if (profile != null) {
      final name = profile.username.isNotEmpty
          ? profile.username
          : (profile.id == widget.me.id ? widget.me.username : '');
      return name.isEmpty ? null : '/profile/$name';
    }
    if (n.post != null) return '/post/${n.post!.id}';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          ListenableBuilder(
            listenable: controller,
            builder: (_, _) {
              final hasUnread = controller.items.any((n) => !n.read);
              return TextButton(
                onPressed: _markingAll || !hasUnread ? null : _markAll,
                child: _markingAll
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('全部已读'),
              );
            },
          ),
        ],
      ),
      body: PagedView<IwaraNotification>(
        controller: controller,
        padding: EdgeInsets.zero,
        layout: const ListLayout(separated: true),
        emptyText: '暂无通知',
        emptyIcon: Icons.notifications_none,
        itemBuilder: (context, n, _) => _NotificationTile(
          notification: n,
          myId: widget.me.id,
          onTap: () => _open(n),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.myId,
    required this.onTap,
  });

  final IwaraNotification notification;
  final String myId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = notification;
    final unread = !n.read;
    final actor = n.comment?.user;
    final commentBody = n.comment?.body.trim() ?? '';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (actor != null)
              UserAvatar(actor,
                  size: 40,
                  onTap: actor.username.isEmpty
                      ? null
                      : () => context.push('/profile/${actor.username}'))
            else
              CircleAvatar(
                radius: 20,
                backgroundColor: scheme.secondaryContainer,
                child: Icon(_iconFor(n.type),
                    size: 22, color: scheme.onSecondaryContainer),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                        children: _describe(
                            n, myId, TextStyle(color: scheme.primary))),
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            unread ? FontWeight.bold : FontWeight.normal),
                  ),
                  if (commentBody.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        commentBody,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    formatAgo(n.createdAt),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ],
              ),
            ),
            if (unread)
              const Padding(
                padding: EdgeInsets.only(left: 8, top: 6),
                child: UnreadDot(),
              ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String type) => switch (type) {
        'newComment' || 'newReply' => Icons.chat_bubble_outline,
        'videoReady' => Icons.video_library_outlined,
        'warning' => Icons.warning_amber_rounded,
        'tagApproved' => Icons.sell_outlined,
        'joinedCreatorProgram' => Icons.workspace_premium_outlined,
        'reviewApproved' => Icons.check_circle_outline,
        'reviewRejected' => Icons.cancel_outlined,
        _ => Icons.notifications_none,
      };

  /// 通知目标的描述。
  static String _target(IwaraNotification n, String myId) {
    if (n.video != null) {
      return n.video!.title.isEmpty ? '视频' : '「${n.video!.title}」';
    }
    if (n.image != null) {
      return n.image!.title.isEmpty ? '图片' : '「${n.image!.title}」';
    }
    if (n.profileUser != null) {
      return n.profileUser!.id == myId ? '你的主页' : 'TA 的主页';
    }
    if (n.post != null) {
      return n.post!.title.isEmpty ? '动态' : '「${n.post!.title}」';
    }
    return '你的内容';
  }

  static List<InlineSpan> _describe(
      IwaraNotification n, String myId, TextStyle em) {
    TextSpan e(String s) => TextSpan(text: s, style: em);
    TextSpan t(String s) => TextSpan(text: s);
    final actor = n.comment?.user?.name ?? '有人';
    return switch (n.type) {
      'newComment' => [e(actor), t(' 在 '), e(_target(n, myId)), t(' 发表了新评论')],
      'newReply' => [e(actor), t(' 回复了你在 '), e(_target(n, myId)), t(' 的评论')],
      'videoReady' => n.video?.title.isNotEmpty == true
          ? [t('你的视频 '), e('「${n.video!.title}」'), t(' 已发布')]
          : [t('你的视频已发布')],
      'warning' => [t('你收到了一条警告')],
      'tagApproved' => [t('你建议的标签 '), e(n.tagId ?? ''), t(' 已通过')],
      'joinedCreatorProgram' => [t('你已加入创作者计划')],
      'reviewApproved' => [t('你的内容已通过审核')],
      'reviewRejected' => [t('你的内容未通过审核')],
      _ => [t(n.type.isEmpty ? '未知通知' : n.type)],
    };
  }
}
