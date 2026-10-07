import 'package:flutter/material.dart';

/// 板块图标（按去掉语言后缀的板块 id）。
IconData forumSectionIcon(String id) {
  final base = id.replaceAll(RegExp(r'-(zh|ja)$'), '');
  return switch (base) {
    'announcements' => Icons.campaign_outlined,
    'feedback' => Icons.feedback_outlined,
    'support' => Icons.support_agent,
    'guides' => Icons.menu_book_outlined,
    'general' => Icons.forum_outlined,
    'questions' => Icons.help_outline,
    'requests' => Icons.pan_tool_outlined,
    'sharing' => Icons.share_outlined,
    _ => Icons.forum_outlined,
  };
}

/// 用户角色标签文字，普通用户返回 null。
String? forumRoleLabel(String? role) => switch (role) {
      'admin' => '管理员',
      'moderator' => '版主',
      _ => null,
    };

/// 小号标签（置顶 / 锁定 / 楼主 等）。
class ForumTag extends StatelessWidget {
  const ForumTag(this.text, {super.key, this.color, this.icon});

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 2),
        ],
        Text(text,
            style: TextStyle(
                color: c,
                fontSize: 10,
                height: 1.3,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// 图标 + 文字的统计项。
class ForumStat extends StatelessWidget {
  const ForumStat(this.icon, this.text, {super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.hintColor;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 3),
      Text(text, style: theme.textTheme.labelSmall?.copyWith(color: color)),
    ]);
  }
}
