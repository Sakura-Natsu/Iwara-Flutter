import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../models/common.dart';
import '../../models/forum.dart';
import '../../models/image.dart';
import '../../models/social.dart';
import '../../models/user.dart';
import '../../models/video.dart';
import '../../providers.dart';
import '../../services/local_db.dart';
import '../../widgets/cards.dart';
import '../../widgets/net_image.dart';
import '../../widgets/paging.dart';

/// 搜索类型。
enum SearchType {
  videos('videos', '视频'),
  images('images', '图片'),
  users('users', '用户'),
  posts('posts', '动态'),
  playlists('playlists', '播放列表'),
  forumThreads('forum_threads', '论坛');

  const SearchType(this.value, this.label);
  final String value;
  final String label;
}

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.initialQuery, this.initialType});

  final String? initialQuery;
  final String? initialType;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _input =
      TextEditingController(text: widget.initialQuery);
  late final TabController _tabs = TabController(
    length: SearchType.values.length,
    vsync: this,
    initialIndex: SearchType.values
        .indexWhere((t) => t.value == widget.initialType)
        .clamp(0, SearchType.values.length - 1),
  );
  final _focus = FocusNode();
  String? query;
  List<String> history = [];

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery?.trim();
    if (q != null && q.isNotEmpty) {
      query = q;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _tabs.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final h = await LocalDb.instance.searchHistory();
    if (mounted) setState(() => history = h);
  }

  void _submit(String text) {
    final q = text.trim();
    if (q.isEmpty) return;
    _input.text = q;
    _focus.unfocus();
    LocalDb.instance
        .addSearch(q, SearchType.values[_tabs.index].value)
        .then((_) => _loadHistory());
    setState(() => query = q);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _input,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          textAlignVertical: TextAlignVertical.center,
          onSubmitted: _submit,
          decoration: InputDecoration(
            hintText: '搜索视频、图片、用户…',
            border: InputBorder.none,
            filled: false,
            isDense: false,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            suffixIcon: ValueListenableBuilder(
              valueListenable: _input,
              builder: (_, v, _) => v.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _input.clear();
                        _focus.requestFocus();
                      },
                    ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => _submit(_input.text), child: const Text('搜索')),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in SearchType.values) Tab(text: t.label)],
        ),
      ),
      body: query == null
          ? _historyView(theme)
          : TabBarView(
              controller: _tabs,
              children: [
                for (final t in SearchType.values)
                  _SearchResults(key: ValueKey('${t.value}:$query'), type: t, query: query!),
              ],
            ),
    );
  }

  Widget _historyView(ThemeData theme) {
    if (history.isEmpty) {
      return Center(
        child: Text('输入关键词开始搜索', style: TextStyle(color: theme.hintColor)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Text('搜索历史', style: theme.textTheme.titleSmall),
          const Spacer(),
          TextButton(
            onPressed: () async {
              await LocalDb.instance.clearSearchHistory();
              _loadHistory();
            },
            child: const Text('清空'),
          ),
        ]),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final h in history)
              InputChip(
                label: Text(h),
                onPressed: () => _submit(h),
                onDeleted: () async {
                  await LocalDb.instance.removeSearch(h);
                  _loadHistory();
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _SearchResults extends ConsumerStatefulWidget {
  const _SearchResults({super.key, required this.type, required this.query});

  final SearchType type;
  final String query;

  @override
  ConsumerState<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends ConsumerState<_SearchResults>
    with AutomaticKeepAliveClientMixin {
  late final PagingController<Object> controller = PagingController(
    (page) => ref.read(apiProvider).search<Object>(
          widget.type.value,
          widget.query,
          _parser(widget.type),
          page: page,
        ),
  );

  static Object Function(Json) _parser(SearchType t) => switch (t) {
        SearchType.videos => Video.fromJson,
        SearchType.images => GalleryImage.fromJson,
        SearchType.users => User.fromJson,
        SearchType.posts => Post.fromJson,
        SearchType.playlists => Playlist.fromJson,
        SearchType.forumThreads => ForumThread.fromJson,
      };

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
    final layout = switch (widget.type) {
      SearchType.videos => kVideoGridLayout,
      SearchType.images => kImageGridLayout,
      _ => const ListLayout(separated: true),
    };
    return PagedView<Object>(
      controller: controller,
      layout: layout,
      padding: layout is GridLayout ? const EdgeInsets.all(8) : EdgeInsets.zero,
      emptyText: '没有找到「${widget.query}」相关的${widget.type.label}',
      emptyIcon: Icons.search_off,
      itemBuilder: (context, item, _) => _item(context, item),
    );
  }

  Widget _item(BuildContext context, Object item) {
    final theme = Theme.of(context);
    return switch (item) {
      Video v => VideoCard(v),
      GalleryImage i => ImageCard(i),
      User u => ListTile(
          leading: UserAvatar(u, size: 40),
          title: Text(u.name),
          subtitle: Text('@${u.username}'),
          onTap: () => context.push('/profile/${u.username}'),
        ),
      Post p => ListTile(
          title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${p.user?.name ?? ''} · ${formatAgo(p.createdAt)}\n${(p.body ?? '').replaceAll('\n', ' ')}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          onTap: () => context.push('/post/${p.id}'),
        ),
      Playlist pl => PlaylistTile(pl),
      ForumThread t => ListTile(
          title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${forumSectionName(t.section)} · ${t.user?.name ?? ''} · ${t.numPosts} 回复',
            style: TextStyle(color: theme.hintColor),
          ),
          trailing: Text(formatAgo(t.updatedAt),
              style: theme.textTheme.labelSmall),
          onTap: () => context.push('/forum/${t.section}/${t.id}'),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}
