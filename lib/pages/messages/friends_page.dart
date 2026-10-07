import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../models/user.dart';
import '../../providers.dart';
import '../../widgets/net_image.dart';
import '../../widgets/paging.dart';
import '../../widgets/states.dart';
import 'common.dart';
import 'new_conversation_page.dart';

/// 好友 / 好友请求。
class FriendsPage extends ConsumerWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    if (me == null) {
      return const LoginRequiredScaffold(
        title: '好友',
        text: '登录后查看好友',
        icon: Icons.people_outline,
      );
    }
    return _FriendsView(key: ValueKey(me.user.id), myId: me.user.id);
  }
}

class _FriendsView extends ConsumerStatefulWidget {
  const _FriendsView({super.key, required this.myId});

  final String myId;

  @override
  ConsumerState<_FriendsView> createState() => _FriendsViewState();
}

class _FriendsViewState extends ConsumerState<_FriendsView> {
  late final PagingController<User> friends = PagingController(
    (page) => ref.read(apiProvider).friends(widget.myId, page: page),
    dedupeKey: (u) => u.id,
  );

  late final PagingController<FriendRequest> requests = PagingController(
    (page) => ref.read(apiProvider).friendRequests(widget.myId, page: page),
    dedupeKey: (r) => r.id,
  );

  /// 正在处理的好友请求 id。
  final Set<String> _busy = {};

  @override
  void dispose() {
    friends.dispose();
    requests.dispose();
    super.dispose();
  }

  // ---------------- 好友 ----------------

  Future<void> _onFriendMenu(User u, String action) async {
    switch (action) {
      case 'message':
        await startConversation(context, ref, recipient: u);
        if (mounted) ref.invalidate(countsProvider);
      case 'remove':
        if (!await confirm(context, '删除好友 ${u.name}？',
            danger: true, okText: '删除')) {
          return;
        }
        if (!mounted) return;
        // 乐观移除，失败回滚
        final index = friends.items.indexWhere((e) => e.id == u.id);
        friends.removeWhere((e) => e.id == u.id);
        try {
          await ref.read(apiProvider).removeFriend(u.id);
          if (mounted) showToast(context, '已删除好友');
        } catch (e) {
          if (index >= 0 && !friends.items.any((x) => x.id == u.id)) {
            friends.insert(index.clamp(0, friends.items.length), u);
          }
          if (mounted) showError(context, e);
        }
    }
  }

  // ---------------- 好友请求 ----------------

  Future<void> _handleRequest(FriendRequest req, String action) async {
    if (_busy.contains(req.id)) return;
    setState(() => _busy.add(req.id));
    final api = ref.read(apiProvider);
    try {
      switch (action) {
        case 'accept':
          await api.addFriend(req.user.id);
        case 'reject':
          await api.removeFriend(req.user.id);
        case 'withdraw':
          await api.removeFriend(req.target.id);
      }
      requests.removeWhere((r) => r.id == req.id);
      if (!mounted) return;
      ref.invalidate(countsProvider);
      showToast(
          context,
          switch (action) {
            'accept' => '已添加好友',
            'reject' => '已拒绝',
            _ => '已撤回请求',
          });
      if (action == 'accept') friends.refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(req.id));
    }
  }

  // ---------------- 界面 ----------------

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(countsProvider).value?.friendRequests ?? 0;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('好友'),
          bottom: TabBar(tabs: [
            const Tab(text: '好友'),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('好友请求'),
                if (pending > 0) ...[
                  const SizedBox(width: 6),
                  Badge.count(count: pending),
                ],
              ]),
            ),
          ]),
        ),
        body: TabBarView(children: [
          _KeepAlive(
            child: PagedView<User>(
              controller: friends,
              primary: false,
              padding: EdgeInsets.zero,
              emptyText: '还没有好友',
              emptyIcon: Icons.people_outline,
              itemBuilder: (context, u, _) => UserListTile(
                user: u,
                subtitle: u.isOnline ? '@${u.username} · 在线' : null,
                trailing: PopupMenuButton<String>(
                  tooltip: '更多',
                  onSelected: (v) => _onFriendMenu(u, v),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'message',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.mail_outline),
                        title: Text('发私信'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.person_remove_outlined,
                            color: Theme.of(ctx).colorScheme.error),
                        title: Text('删除好友',
                            style: TextStyle(
                                color: Theme.of(ctx).colorScheme.error)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _KeepAlive(
            child: PagedView<FriendRequest>(
              controller: requests,
              primary: false,
              padding: EdgeInsets.zero,
              emptyText: '暂无好友请求',
              emptyIcon: Icons.person_add_alt_outlined,
              itemBuilder: (context, r, _) => _RequestTile(
                request: r,
                myId: widget.myId,
                busy: _busy.contains(r.id),
                onAction: (action) => _handleRequest(r, action),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.myId,
    required this.busy,
    required this.onAction,
  });

  final FriendRequest request;
  final String myId;
  final bool busy;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final incoming = request.target.id == myId;
    final outgoing = !incoming && request.user.id == myId;
    final other = incoming ? request.user : request.target;
    final ago = formatAgo(request.createdAt);
    final status = incoming
        ? '请求添加你为好友'
        : outgoing
            ? '等待对方通过'
            : '';
    const dense = VisualDensity.compact;

    Widget? trailing;
    if (busy) {
      trailing = const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2));
    } else if (incoming) {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton(
          style: TextButton.styleFrom(visualDensity: dense),
          onPressed: () => onAction('reject'),
          child: const Text('拒绝'),
        ),
        const SizedBox(width: 4),
        FilledButton.tonal(
          style: FilledButton.styleFrom(visualDensity: dense),
          onPressed: () => onAction('accept'),
          child: const Text('接受'),
        ),
      ]);
    } else if (outgoing) {
      trailing = OutlinedButton(
        style: OutlinedButton.styleFrom(visualDensity: dense),
        onPressed: () => onAction('withdraw'),
        child: const Text('撤回'),
      );
    }

    return ListTile(
      onTap: other.username.isEmpty
          ? null
          : () => context.push('/profile/${other.username}'),
      leading: UserAvatar(other, size: 42),
      title: Text(other.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [status, ago].where((s) => s.isNotEmpty).join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
    );
  }
}

/// 保持 TabBarView 子页状态。
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
