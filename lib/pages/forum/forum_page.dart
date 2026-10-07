import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../models/forum.dart';
import '../../providers.dart';
import '../../widgets/states.dart';
import 'forum_widgets.dart';

/// 分组显示顺序：站务、中文优先，其余按接口返回顺序。
const _groupOrder = ['administration', 'chinese', 'global', 'japanese'];

/// 论坛首页（底部导航 Tab）：按分组列出板块。
class ForumPage extends ConsumerStatefulWidget {
  const ForumPage({super.key});

  @override
  ConsumerState<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends ConsumerState<ForumPage> {
  List<ForumSection>? _sections;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(apiProvider).forumSections();
      if (!mounted) return;
      setState(() {
        _sections = list;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      // 已有数据时只提示，不覆盖列表
      if (_sections == null) {
        setState(() => _error = e);
      } else {
        showError(context, e);
      }
    }
  }

  void _retry() {
    setState(() => _error = null);
    _load();
  }

  /// 按 group 分组并排序。
  List<(String, List<ForumSection>)> _grouped(List<ForumSection> list) {
    final map = <String, List<ForumSection>>{};
    for (final s in list) {
      map.putIfAbsent(s.group, () => []).add(s);
    }
    int rank(String g) {
      final i = _groupOrder.indexOf(g);
      return i < 0 ? _groupOrder.length : i;
    }

    final keys = map.keys.toList();
    // 稳定排序：未知分组保持原顺序
    final indexed = [for (var i = 0; i < keys.length; i++) (i, keys[i])];
    indexed.sort((a, b) {
      final r = rank(a.$2).compareTo(rank(b.$2));
      return r != 0 ? r : a.$1.compareTo(b.$1);
    });
    return [for (final (_, g) in indexed) (g, map[g]!)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('论坛'),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search?type=forum_threads'),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final sections = _sections;
    if (sections == null) {
      return _error != null
          ? ErrorView.from(_error!, onRetry: _retry)
          : const LoadingView();
    }
    final groups = _grouped(sections);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          if (groups.isEmpty)
            const SizedBox(
                height: 360, child: EmptyView(text: '暂无板块', icon: Icons.forum_outlined)),
          for (final (group, list) in groups) ...[
            _GroupHeader(forumGroupName(group)),
            for (final s in list) _SectionCard(section: s),
          ],
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(title,
          style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
    );
  }
}

/// 板块卡片：名称、简介、统计、最新主题。
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final ForumSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = section;
    final desc = forumSectionDesc(s.id);
    final last = s.lastThread;
    final stats = [
      '主题 ${formatCount(s.numThreads)}',
      // 中文/日文板块接口返回的帖子数为 0，不显示
      if (s.numPosts > 0) '帖子 ${formatCount(s.numPosts)}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/forum/${s.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(forumSectionIcon(s.id),
                      color: scheme.onPrimaryContainer, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(forumSectionName(s.id),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        if (s.locked) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.lock_outline,
                              size: 16, color: theme.hintColor),
                        ],
                      ]),
                      if (desc.isNotEmpty)
                        Text(desc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.hintColor)),
                      const SizedBox(height: 2),
                      Text(stats,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.hintColor)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: theme.hintColor),
              ]),
              if (last != null) ...[
                const SizedBox(height: 8),
                _LastThreadRow(thread: last),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 最新主题，点击直接进入该主题。
class _LastThreadRow extends StatelessWidget {
  const _LastThreadRow({required this.thread});

  final ForumThread thread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = thread;
    final time = t.lastPost?.createdAt ?? t.updatedAt ?? t.createdAt;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/forum/${t.section}/${t.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            Icon(Icons.chat_bubble_outline, size: 14, color: theme.hintColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall),
            ),
            const SizedBox(width: 8),
            Text(formatAgo(time),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.hintColor)),
          ]),
        ),
      ),
    );
  }
}
