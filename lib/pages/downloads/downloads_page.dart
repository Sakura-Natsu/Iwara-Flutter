import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../providers.dart';
import '../../services/download_service.dart';
import '../../widgets/net_image.dart';
import '../../widgets/states.dart';

/// 离线下载管理。
class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});

  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  List<TaskRecord>? records;
  final progress = <String, TaskProgressUpdate>{};
  StreamSubscription? _sub;
  Timer? _reloadTimer;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _reload();
    // 排队中的任务没有进度回调，定时刷新以更新等待提示
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted &&
          (records?.any((r) => r.status == TaskStatus.enqueued) ?? false)) {
        setState(() {});
      }
    });
    _sub = DownloadService.changes.stream.listen((u) {
      if (u is TaskProgressUpdate) {
        // 负值是特殊标记（暂停 -5、失败 -1 等），不作为进度显示
        if (u.progress < 0) return;
        setState(() => progress[u.task.taskId] = u);
      } else {
        _reloadTimer?.cancel();
        _reloadTimer = Timer(const Duration(milliseconds: 300), _reload);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reloadTimer?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  /// 已完成文件的实际大小（记录里的 expectedFileSize 可能缺失）。
  final fileSizes = <String, int>{};

  Future<void> _reload() async {
    final list = await DownloadService.records();
    for (final r in list) {
      if (r.status == TaskStatus.complete && !fileSizes.containsKey(r.taskId)) {
        try {
          fileSizes[r.taskId] = await File(
            await DownloadService.filePath(r),
          ).length();
        } catch (_) {}
      }
    }
    if (mounted) setState(() => records = list);
  }

  Future<void> _open(TaskRecord r, DownloadMeta? meta) async {
    final path = await DownloadService.filePath(r);
    if (!mounted) return;
    final q = Uri(
      queryParameters: {
        'path': path,
        'title': meta?.title ?? r.task.displayName,
        if (meta != null) 'id': meta.videoId,
      },
    ).query;
    context.push('/local-video?$q');
  }

  /// 失败的任务：直链可能已过期，重新获取后再下载。
  Future<void> _retry(TaskRecord r, DownloadMeta? meta) async {
    if (meta == null) {
      await DownloadService.retry(r.task);
      return;
    }
    showToast(context, '正在重新获取下载地址…');
    try {
      final api = ref.read(apiProvider);
      final v = await api.video(meta.videoId);
      final sources = await api.videoSources(v);
      final src = sources.firstWhere(
        (s) => s.name == meta.quality,
        orElse: () => sources.first,
      );
      await DownloadService.delete(r);
      await DownloadService.enqueue(v, src);
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(TaskRecord r) async {
    final done = r.status == TaskStatus.complete;
    if (!await confirm(
      context,
      done ? '删除已下载的视频？' : '取消并删除该任务？',
      danger: true,
      okText: '删除',
    )) {
      return;
    }
    await DownloadService.delete(r);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final list = records;
    return Scaffold(
      appBar: AppBar(title: const Text('离线下载')),
      body: list == null
          ? const LoadingView()
          : list.isEmpty
          ? const EmptyView(
              text: '还没有下载任务\n在视频页点击「下载」即可离线观看',
              icon: Icons.download_outlined,
            )
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) => _item(list[i]),
              ),
            ),
    );
  }

  Widget _item(TaskRecord r) {
    final theme = Theme.of(context);
    final meta = DownloadMeta.parse(r.task.metaData);
    final p = progress[r.taskId];
    final status = r.status;
    // progress 表只保存有效（非负）的进度；数据库中暂停时可能记录为负值
    final pct = (p?.progress ?? (r.progress < 0 ? 0.0 : r.progress)).clamp(
      0.0,
      1.0,
    );
    final size = p?.expectedFileSize ?? r.expectedFileSize;

    String statusText;
    switch (status) {
      case TaskStatus.complete:
        final done = fileSizes[r.taskId] ?? size;
        statusText = '已完成${done > 0 ? ' · ${formatBytes(done)}' : ''}';
      case TaskStatus.running:
        final speed = p != null && p.networkSpeed > 0
            ? ' · ${p.networkSpeed.toStringAsFixed(1)} MB/s'
            : '';
        statusText = '下载中 ${(pct * 100).toStringAsFixed(0)}%$speed';
      case TaskStatus.enqueued:
        final waited = DateTime.now().difference(r.task.creationTime);
        statusText = waited.inSeconds > 20 ? '等待网络…' : '等待中';
      case TaskStatus.paused:
        statusText = '已暂停 ${(pct * 100).toStringAsFixed(0)}%';
      case TaskStatus.waitingToRetry:
        statusText = '等待重试';
      case TaskStatus.failed:
      case TaskStatus.notFound:
        statusText = '下载失败';
      case TaskStatus.canceled:
        statusText = '已取消';
    }

    final active =
        status == TaskStatus.running ||
        status == TaskStatus.enqueued ||
        status == TaskStatus.waitingToRetry;

    return InkWell(
      onTap: status == TaskStatus.complete ? () => _open(r, meta) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(
                      meta?.thumbnail,
                      borderRadius: BorderRadius.circular(6),
                      placeholderIcon: Icons.movie_outlined,
                    ),
                    if (status == TaskStatus.complete)
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          color: Colors.white70,
                          size: 32,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta?.title ?? r.task.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (meta?.author != null) meta!.author!,
                      if (meta?.quality != null)
                        meta!.quality == 'Source' ? '原画' : '${meta.quality}P',
                      statusText,
                    ].join(' · '),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: status == TaskStatus.failed
                          ? theme.colorScheme.error
                          : theme.hintColor,
                    ),
                  ),
                  if (status != TaskStatus.complete) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: status == TaskStatus.enqueued ? null : pct,
                    ),
                  ],
                  if (status == TaskStatus.enqueued &&
                      DateTime.now().difference(r.task.creationTime).inSeconds >
                          20) ...[
                    const SizedBox(height: 4),
                    Text(
                      '系统判定当前网络不可用（常见于无法访问 Google 连通性检测、且未开启 VPN 时），'
                      '下载会在网络可用后自动开始。可将代理软件切换为 VPN 模式。',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (status == TaskStatus.running)
              IconButton(
                tooltip: '暂停',
                icon: const Icon(Icons.pause),
                onPressed: () => DownloadService.pause(r.task),
              )
            else if (status == TaskStatus.paused)
              IconButton(
                tooltip: '继续',
                icon: const Icon(Icons.play_arrow),
                onPressed: () async {
                  final ok = await DownloadService.resume(r.task);
                  if (!ok) await _retry(r, meta);
                },
              )
            else if (status == TaskStatus.failed ||
                status == TaskStatus.notFound ||
                status == TaskStatus.canceled)
              IconButton(
                tooltip: '重试',
                icon: const Icon(Icons.refresh),
                onPressed: () => _retry(r, meta),
              ),
            IconButton(
              tooltip: active ? '取消' : '删除',
              icon: Icon(active ? Icons.close : Icons.delete_outline),
              onPressed: () => _delete(r),
            ),
          ],
        ),
      ),
    );
  }
}
