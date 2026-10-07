import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/settings.dart';

/// 列表筛选条件（标签 + 年月）。分级来自全局设置。
@immutable
class ContentFilter {
  const ContentFilter({this.tags = const [], this.date});

  final List<String> tags;

  /// 形如 2024 或 2024-5
  final String? date;

  bool get isEmpty => tags.isEmpty && date == null;

  ContentFilter copyWith({List<String>? tags, String? date, bool clearDate = false}) =>
      ContentFilter(
        tags: tags ?? this.tags,
        date: clearDate ? null : (date ?? this.date),
      );

  @override
  bool operator ==(Object other) =>
      other is ContentFilter &&
      other.date == date &&
      other.tags.join(',') == tags.join(',');

  @override
  int get hashCode => Object.hash(date, tags.join(','));
}

class ContentFilterNotifier extends Notifier<ContentFilter> {
  @override
  ContentFilter build() => const ContentFilter();

  void set(ContentFilter f) => state = f;
}

final videoFilterProvider =
    NotifierProvider<ContentFilterNotifier, ContentFilter>(
        ContentFilterNotifier.new);

final imageFilterProvider =
    NotifierProvider<ContentFilterNotifier, ContentFilter>(
        ContentFilterNotifier.new);

/// 筛选面板。返回 true 表示有修改。
Future<void> showFilterSheet(
  BuildContext context,
  WidgetRef ref,
  NotifierProvider<ContentFilterNotifier, ContentFilter> provider,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _FilterSheet(provider: provider),
  );
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.provider});

  final NotifierProvider<ContentFilterNotifier, ContentFilter> provider;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late Rating rating = ref.read(settingsProvider).rating;
  late List<String> tags = [...ref.read(widget.provider).tags];
  int? year;
  int? month;

  @override
  void initState() {
    super.initState();
    final d = ref.read(widget.provider).date;
    if (d != null) {
      final parts = d.split('-');
      year = int.tryParse(parts[0]);
      if (parts.length > 1) month = int.tryParse(parts[1]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final years = [for (var y = now.year; y >= 2014; y--) y];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('分级', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<Rating>(
              segments: [
                for (final r in Rating.values)
                  ButtonSegment(value: r, label: Text(r.label)),
              ],
              selected: {rating},
              onSelectionChanged: (s) => setState(() => rating = s.first),
            ),
            const SizedBox(height: 16),
            Text('分类', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (id, label) in kCategoryTags)
                  FilterChip(
                    label: Text(label),
                    selected: tags.contains(id),
                    onSelected: (v) => setState(() {
                      v ? tags.add(id) : tags.remove(id);
                    }),
                  ),
                for (final t in tags.where(
                    (t) => !kCategoryTags.any((c) => c.$1 == t)))
                  InputChip(
                    label: Text(t),
                    selected: true,
                    onDeleted: () => setState(() => tags.remove(t)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('发布时间', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: year,
                  decoration: const InputDecoration(labelText: '年份'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('不限')),
                    for (final y in years)
                      DropdownMenuItem(value: y, child: Text('$y 年')),
                  ],
                  onChanged: (v) => setState(() {
                    year = v;
                    if (v == null) month = null;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: month,
                  decoration: const InputDecoration(labelText: '月份'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('不限')),
                    for (var m = 1; m <= 12; m++)
                      DropdownMenuItem(value: m, child: Text('$m 月')),
                  ],
                  onChanged: year == null
                      ? null
                      : (v) => setState(() => month = v),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              TextButton(
                onPressed: () => setState(() {
                  tags = [];
                  year = null;
                  month = null;
                }),
                child: const Text('重置'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _apply,
                child: const Text('应用'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _apply() {
    final settings = ref.read(settingsProvider);
    if (settings.rating != rating) {
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(rating: rating));
    }
    final date = year == null ? null : (month == null ? '$year' : '$year-$month');
    ref.read(widget.provider.notifier).set(ContentFilter(tags: tags, date: date));
    Navigator.pop(context);
  }
}
