import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/social.dart';
import '../../providers.dart';
import '../../widgets/states.dart';

Future<void> showAddToPlaylistSheet(BuildContext context, String videoId) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _AddToPlaylistSheet(videoId: videoId),
  );
}

class _AddToPlaylistSheet extends ConsumerStatefulWidget {
  const _AddToPlaylistSheet({required this.videoId});

  final String videoId;

  @override
  ConsumerState<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<_AddToPlaylistSheet> {
  List<LightPlaylist>? lists;
  Object? error;
  final busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final l = await ref.read(apiProvider).lightPlaylists(widget.videoId);
      if (mounted) setState(() => lists = l);
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> _toggle(int i) async {
    final p = lists![i];
    if (busy.contains(p.id)) return;
    setState(() => busy.add(p.id));
    final api = ref.read(apiProvider);
    try {
      if (p.added) {
        await api.removeFromPlaylist(p.id, widget.videoId);
      } else {
        await api.addToPlaylist(p.id, widget.videoId);
      }
      if (!mounted) return;
      setState(() => lists![i] = p.copyWith(
          added: !p.added, numVideos: p.numVideos + (p.added ? -1 : 1)));
      showToast(context, p.added ? '已从「${p.title}」移除' : '已加入「${p.title}」');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy.remove(p.id));
    }
  }

  Future<void> _create() async {
    final title = await promptText(context, '新建播放列表', hint: '名称');
    if (title == null || title.isEmpty) return;
    try {
      await ref.read(apiProvider).createPlaylist(title);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Text('加入播放列表', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                  label: const Text('新建'),
                ),
              ]),
            ),
            Flexible(
              child: error != null
                  ? ErrorView.from(error!, onRetry: _load)
                  : lists == null
                      ? const Padding(
                          padding: EdgeInsets.all(32), child: LoadingView())
                      : lists!.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(32),
                              child: EmptyView(text: '还没有播放列表'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: lists!.length,
                              itemBuilder: (_, i) {
                                final p = lists![i];
                                return CheckboxListTile(
                                  value: p.added,
                                  onChanged: busy.contains(p.id)
                                      ? null
                                      : (_) => _toggle(i),
                                  title: Text(p.title),
                                  subtitle: Text('${p.numVideos} 个视频'),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
