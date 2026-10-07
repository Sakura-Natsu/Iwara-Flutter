import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';

import '../api/urls.dart';
import '../models/video.dart';

/// 下载任务附带的视频信息（存于 task.metaData）。
class DownloadMeta {
  const DownloadMeta({
    required this.videoId,
    required this.title,
    this.author,
    this.thumbnail,
    this.quality,
    this.duration,
  });

  final String videoId;
  final String title;
  final String? author;
  final String? thumbnail;
  final String? quality;
  final int? duration;

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'title': title,
    'author': author,
    'thumbnail': thumbnail,
    'quality': quality,
    'duration': duration,
  };

  static DownloadMeta? parse(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return DownloadMeta(
        videoId: j['videoId'] as String,
        title: j['title'] as String? ?? '',
        author: j['author'] as String?,
        thumbnail: j['thumbnail'] as String?,
        quality: j['quality'] as String?,
        duration: j['duration'] as int?,
      );
    } catch (_) {
      return null;
    }
  }
}

abstract final class DownloadService {
  static const group = 'videos';
  static final _fd = FileDownloader();

  /// 任务状态变化广播（下载页订阅）。
  static final changes = StreamController<TaskUpdate>.broadcast();

  /// 已删除、但可能还会收到状态回调的任务 id。
  static final _deleted = <String>{};

  static Future<void> init({String? proxy}) async {
    try {
      _fd.configureNotification(
        running: const TaskNotification('正在下载', '{displayName}'),
        complete: const TaskNotification('下载完成', '{displayName}'),
        error: const TaskNotification('下载失败', '{displayName}'),
        paused: const TaskNotification('已暂停', '{displayName}'),
        progressBar: true,
      );
      _fd.updates.listen((u) async {
        // 已删除的任务晚到的「已取消」等状态会被 trackTasks 写回数据库，这里再删一次
        final id = u.task.taskId;
        if (_deleted.contains(id)) {
          if (u is TaskStatusUpdate && u.status.isFinalState) {
            await _fd.database.deleteRecordWithId(id);
            _deleted.remove(id);
          }
          return;
        }
        changes.add(u);
      });
      await _fd.start();
      await applyProxy(proxy);
    } catch (e) {
      debugPrint('下载器初始化失败: $e');
    }
  }

  static Future<void> applyProxy(String? hostPort) async {
    try {
      if (hostPort == null) {
        await _fd.configure(globalConfig: (Config.proxy, false));
      } else {
        final i = hostPort.lastIndexOf(':');
        final host = hostPort.substring(0, i);
        final port = int.parse(hostPort.substring(i + 1));
        await _fd.configure(globalConfig: (Config.proxy, (host, port)));
      }
    } catch (e) {
      debugPrint('设置下载代理失败: $e');
    }
  }

  /// 加入下载队列，返回是否成功。同一视频同一清晰度已在列表中（未失败）时返回 false。
  static Future<bool> enqueue(Video video, VideoSource source) async {
    if (Platform.isAndroid) {
      // Android 13+ 需要通知权限才能显示下载进度
      await _fd.permissions.request(PermissionType.notifications);
    }
    for (final r in await _fd.database.allRecords(group: group)) {
      final m = DownloadMeta.parse(r.task.metaData);
      final alive =
          r.status != TaskStatus.failed &&
          r.status != TaskStatus.canceled &&
          r.status != TaskStatus.notFound;
      if (alive && m?.videoId == video.id && m?.quality == source.name) {
        return false;
      }
    }
    // 每次入队使用新的 taskId，避免与已删除旧任务的延迟回调冲突
    final id =
        '${video.id}_${source.name}_${DateTime.now().millisecondsSinceEpoch}';
    final meta = DownloadMeta(
      videoId: video.id,
      title: video.title,
      author: video.user?.name,
      thumbnail: IwaraUrls.videoThumbnail(video),
      quality: source.name,
      duration: video.durationSeconds,
    );
    final task = DownloadTask(
      taskId: id,
      url: source.downloadUrl.isNotEmpty ? source.downloadUrl : source.viewUrl,
      filename: '${video.id}_${source.name}.mp4',
      directory: 'downloads',
      baseDirectory: BaseDirectory.applicationSupport,
      group: group,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 3,
      displayName: video.title,
      metaData: jsonEncode(meta.toJson()),
    );
    return _fd.enqueue(task);
  }

  static Future<List<TaskRecord>> records() async {
    final list = (await _fd.database.allRecords(
      group: group,
    )).where((r) => !_deleted.contains(r.taskId)).toList();
    list.sort((a, b) => b.task.creationTime.compareTo(a.task.creationTime));
    return list;
  }

  static Future<TaskRecord?> recordFor(String videoId) async {
    final list = await _fd.database.allRecords(group: group);
    for (final r in list) {
      if (r.status == TaskStatus.complete &&
          DownloadMeta.parse(r.task.metaData)?.videoId == videoId) {
        return r;
      }
    }
    return null;
  }

  static Future<bool> pause(Task task) =>
      task is DownloadTask ? _fd.pause(task) : Future.value(false);

  static Future<bool> resume(Task task) =>
      task is DownloadTask ? _fd.resume(task) : Future.value(false);

  /// 失败的任务重新排队（直链可能已过期，调用方应先更新 url）。
  static Future<bool> retry(Task task) => _fd.enqueue(task);

  static Future<void> delete(TaskRecord record) async {
    if (record.status.isNotFinalState) _deleted.add(record.taskId);
    await _fd.cancelTaskWithId(record.taskId);
    await _fd.database.deleteRecordWithId(record.taskId);
    try {
      final f = File(await record.task.filePath());
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static Future<String> filePath(TaskRecord record) => record.task.filePath();
}
