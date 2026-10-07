import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../models/common.dart';
import 'states.dart';

typedef PageFetcher<T> = Future<PageResult<T>> Function(int page);

/// 无限滚动分页控制器。
class PagingController<T> extends ChangeNotifier {
  PagingController(this.fetcher, {this.dedupeKey});

  PageFetcher<T> fetcher;

  /// 用于去重（翻页期间列表变化会导致重复项）。
  final Object Function(T item)? dedupeKey;

  final List<T> items = [];
  int _nextPage = 0;
  bool loading = false;
  bool hasMore = true;
  Object? error;
  bool _disposed = false;
  int _generation = 0;

  bool get isEmpty => items.isEmpty;
  bool get initialLoading => loading && items.isEmpty;

  /// 刷新。[silent] 为 true 时保留现有列表直到第一页返回（无加载闪烁）。
  Future<void> refresh({bool silent = false}) async {
    if (silent && items.isNotEmpty) return _silentRefresh();
    _generation++;
    items.clear();
    _nextPage = 0;
    hasMore = true;
    error = null;
    loading = false;
    _notify();
    await loadMore();
  }

  Future<void> _silentRefresh() async {
    final gen = ++_generation;
    loading = true; // 阻止刷新期间的 loadMore 用旧页码请求
    try {
      final res = await fetcher(0);
      if (gen != _generation || _disposed) return;
      items.clear();
      _nextPage = 0;
      _append(res);
      error = null;
    } catch (e) {
      if (gen != _generation || _disposed) return;
    }
    if (gen == _generation) loading = false;
    _notify();
  }

  /// 追加一页并更新 hasMore（videos 等接口的 count = 已加载数 + 1 表示还有更多）。
  void _append(PageResult<T> res) {
    final keyFn = dedupeKey;
    if (keyFn != null) {
      final seen = items.map(keyFn).toSet();
      items.addAll(res.results.where((e) => seen.add(keyFn(e))));
    } else {
      items.addAll(res.results);
    }
    _nextPage++;
    final limit = res.limit > 0 ? res.limit : 32;
    hasMore =
        res.results.length >= limit &&
        (res.count == null || res.count! > items.length || res.count! <= 0);
  }

  Future<void> loadMore() async {
    if (loading || !hasMore) return;
    loading = true;
    error = null;
    _notify();
    final gen = _generation;
    try {
      final res = await fetcher(_nextPage);
      if (gen != _generation || _disposed) return;
      _append(res);
    } catch (e) {
      if (gen != _generation || _disposed) return;
      error = e;
    } finally {
      if (gen == _generation) loading = false;
      _notify();
    }
  }

  void updateWhere(bool Function(T) test, T Function(T) update) {
    for (var i = 0; i < items.length; i++) {
      if (test(items[i])) items[i] = update(items[i]);
    }
    _notify();
  }

  void removeWhere(bool Function(T) test) {
    items.removeWhere(test);
    _notify();
  }

  void insert(int index, T item) {
    items.insert(index, item);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 布局方式。
sealed class PagedLayout {
  const PagedLayout();
}

class ListLayout extends PagedLayout {
  const ListLayout({this.separated = false});
  final bool separated;
}

/// 自适应列数网格：每项宽度约 [itemWidth]，高度 = 宽度 / [aspectRatio] + [extraHeight]。
class GridLayout extends PagedLayout {
  const GridLayout({
    this.itemWidth = 200,
    this.aspectRatio = 16 / 9,
    this.extraHeight = 64,
    this.minColumns = 2,
    this.spacing = 8,
  });

  final double itemWidth;
  final double aspectRatio;
  final double extraHeight;
  final int minColumns;
  final double spacing;
}

/// 分页列表/网格。controller 由外部持有（可跨 rebuild 保持），首次显示时自动加载。
class PagedView<T> extends StatefulWidget {
  const PagedView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.layout = const ListLayout(),
    this.headerSlivers = const [],
    this.padding = const EdgeInsets.all(8),
    this.emptyText = '这里什么都没有',
    this.emptyIcon = Icons.inbox_outlined,
    this.scrollController,
    this.primary,
    this.enableRefresh = true,
  });

  final PagingController<T> controller;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final PagedLayout layout;
  final List<Widget> headerSlivers;
  final EdgeInsets padding;
  final String emptyText;
  final IconData emptyIcon;
  final ScrollController? scrollController;
  final bool? primary;
  final bool enableRefresh;

  @override
  State<PagedView<T>> createState() => _PagedViewState<T>();
}

class _PagedViewState<T> extends State<PagedView<T>> {
  PagingController<T> get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    if (c.items.isEmpty && !c.loading && c.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.loadMore());
    }
  }

  @override
  void didUpdateWidget(covariant PagedView<T> old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
      if (c.items.isEmpty && !c.loading) c.loadMore();
    }
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical &&
        n.metrics.pixels >= n.metrics.maxScrollExtent - 600) {
      if (c.error == null) c.loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final slivers = <Widget>[
      ...widget.headerSlivers,
      if (c.initialLoading)
        const SliverFillRemaining(hasScrollBody: false, child: LoadingView())
      else if (c.items.isEmpty && c.error != null)
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorView(
            message: ApiException.from(c.error!).message,
            onRetry: c.refresh,
          ),
        )
      else if (c.items.isEmpty && !c.hasMore)
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyView(text: widget.emptyText, icon: widget.emptyIcon),
        )
      else ...[
        SliverPadding(padding: widget.padding, sliver: _buildItems()),
        SliverToBoxAdapter(child: _footer()),
      ],
    ];

    Widget view = NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: CustomScrollView(
        controller: widget.scrollController,
        primary: widget.primary,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: slivers,
      ),
    );
    if (widget.enableRefresh) {
      view = RefreshIndicator(onRefresh: c.refresh, child: view);
    }
    return view;
  }

  Widget _buildItems() {
    final layout = widget.layout;
    switch (layout) {
      case ListLayout(:final separated):
        return SliverList.builder(
          itemCount: c.items.length,
          itemBuilder: (ctx, i) {
            final child = widget.itemBuilder(ctx, c.items[i], i);
            return separated && i > 0
                ? Column(children: [const Divider(height: 1), child])
                : child;
          },
        );
      case GridLayout():
        return SliverLayoutBuilder(
          builder: (ctx, constraints) {
            final width = constraints.crossAxisExtent;
            final cols = (width / layout.itemWidth).floor().clamp(
              layout.minColumns,
              8,
            );
            final itemW = (width - layout.spacing * (cols - 1)) / cols;
            return SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: layout.spacing,
                mainAxisSpacing: layout.spacing,
                mainAxisExtent: itemW / layout.aspectRatio + layout.extraHeight,
              ),
              itemCount: c.items.length,
              itemBuilder: (ctx, i) => widget.itemBuilder(ctx, c.items[i], i),
            );
          },
        );
    }
  }

  Widget _footer() {
    if (c.error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: TextButton.icon(
            onPressed: c.loadMore,
            icon: const Icon(Icons.refresh),
            label: Text('加载失败：${ApiException.from(c.error!).message}，点击重试'),
          ),
        ),
      );
    }
    if (c.loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!c.hasMore) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Center(
          child: Text(
            '— 到底了 —',
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
          ),
        ),
      );
    }
    return const SizedBox(height: 48);
  }
}
