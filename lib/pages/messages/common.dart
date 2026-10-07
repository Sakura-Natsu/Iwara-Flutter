import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/user.dart';
import '../../widgets/net_image.dart';
import '../../widgets/states.dart';

/// 未登录时的占位页面（通知 / 私信 / 好友共用）。
class LoginRequiredScaffold extends StatelessWidget {
  const LoginRequiredScaffold({
    super.key,
    required this.title,
    required this.text,
    this.icon = Icons.lock_outline,
  });

  final String title;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: EmptyView(
          text: text,
          icon: icon,
          action: FilledButton(
            onPressed: () => context.push('/login'),
            child: const Text('去登录'),
          ),
        ),
      );
}

/// 未读圆点。
class UnreadDot extends StatelessWidget {
  const UnreadDot({super.key, this.size = 8});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
      );
}

/// 用户条目：头像 + 昵称 + @用户名。
class UserListTile extends StatelessWidget {
  const UserListTile({
    super.key,
    required this.user,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  final User user;

  /// 默认显示 @用户名。
  final String? subtitle;
  final Widget? trailing;

  /// 默认进入用户主页。
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      enabled: enabled,
      onTap: onTap ?? () => context.push('/profile/${user.username}'),
      leading: Stack(clipBehavior: Clip.none, children: [
        UserAvatar(user, size: 42),
        if (user.isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.surface, width: 2),
              ),
            ),
          ),
      ]),
      title: Text(
        user.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: user.premium ? TextStyle(color: Colors.amber.shade700) : null,
      ),
      subtitle: Text(
        subtitle ?? '@${user.username}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
    );
  }
}
