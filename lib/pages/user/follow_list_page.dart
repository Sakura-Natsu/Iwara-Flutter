import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/iwara_api.dart';
import '../../models/common.dart';
import '../../models/user.dart';
import '../../providers.dart';
import '../../widgets/net_image.dart';
import '../../widgets/paging.dart';

/// 关注 / 粉丝列表。
class FollowListPage extends StatefulWidget {
  const FollowListPage({
    super.key,
    required this.userId,
    this.name,
    this.showFollowing = false,
  });

  final String userId;
  final String? name;
  final bool showFollowing;

  @override
  State<FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends State<FollowListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.showFollowing ? 0 : 1,
  )..addListener(_onTab);

  void _onTab() {
    if (!_tabs.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = _tabs.index == 0 ? '关注' : '粉丝';
    final name = widget.name;
    return Scaffold(
      appBar: AppBar(
        title: Text(name == null || name.isEmpty ? kind : '$name 的$kind'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '关注'),
            Tab(text: '粉丝'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _UserList(
            key: const PageStorageKey('following'),
            emptyText: '还没有关注任何人',
            fetch: (api, page) => api.following(widget.userId, page: page),
          ),
          _UserList(
            key: const PageStorageKey('followers'),
            emptyText: '还没有粉丝',
            fetch: (api, page) => api.followers(widget.userId, page: page),
          ),
        ],
      ),
    );
  }
}

class _UserList extends ConsumerStatefulWidget {
  const _UserList({super.key, required this.fetch, required this.emptyText});

  final Future<PageResult<User>> Function(IwaraApi api, int page) fetch;
  final String emptyText;

  @override
  ConsumerState<_UserList> createState() => _UserListState();
}

class _UserListState extends ConsumerState<_UserList>
    with AutomaticKeepAliveClientMixin {
  late final PagingController<User> controller = PagingController(
    (page) => widget.fetch(ref.read(apiProvider), page),
    dedupeKey: (u) => u.id,
  );

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PagedView<User>(
      controller: controller,
      padding: const EdgeInsets.symmetric(vertical: 4),
      emptyText: widget.emptyText,
      emptyIcon: Icons.people_outline,
      itemBuilder: (context, u, _) => UserListTile(u),
    );
  }
}

/// 用户列表条目：头像、名字、@用户名，点击进入主页。
class UserListTile extends StatelessWidget {
  const UserListTile(this.user, {super.key, this.trailing});

  final User user;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: () => context.push('/profile/${user.username}'),
      leading: UserAvatar(user, size: 44),
      title: Row(
        children: [
          Flexible(
            child: Text(
              user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: user.premium
                  ? TextStyle(color: Colors.amber.shade700)
                  : null,
            ),
          ),
          if (user.isOnline) ...[
            const SizedBox(width: 6),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '@${user.username}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: theme.hintColor),
      ),
      trailing: trailing,
    );
  }
}
