typedef Json = Map<String, dynamic>;

DateTime? parseDate(dynamic v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

int parseInt(dynamic v, [int fallback = 0]) => switch (v) {
      int i => i,
      double d => d.toInt(),
      String s => int.tryParse(s) ?? fallback,
      _ => fallback,
    };

int? parseIntOrNull(dynamic v) => switch (v) {
      int i => i,
      double d => d.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };

Json? asJson(dynamic v) => v is Map ? v.cast<String, dynamic>() : null;

/// 解析列表；单条数据异常（如关联用户已注销为 null）时跳过该条，不影响整页。
List<T> parseList<T>(dynamic v, T Function(Json) fn) {
  if (v is! List) return <T>[];
  final out = <T>[];
  for (final e in v.whereType<Map>()) {
    try {
      out.add(fn(e.cast<String, dynamic>()));
    } catch (_) {}
  }
  return out;
}

/// 分页结果。
class PageResult<T> {
  const PageResult({
    required this.results,
    this.count,
    this.limit = 32,
    this.page = 0,
  });

  final List<T> results;
  final int? count;
  final int limit;
  final int page;

  factory PageResult.fromJson(Json j, T Function(Json) fn,
      {String key = 'results'}) {
    return PageResult(
      results: parseList(j[key], fn),
      count: parseIntOrNull(j['count']),
      limit: parseInt(j['limit'], 32),
      page: parseInt(j['page']),
    );
  }
}

/// 文件（视频文件、图片、头像等）。
class IwaraFile {
  const IwaraFile({
    required this.id,
    this.type,
    this.path,
    this.name,
    this.mime,
    this.size,
    this.width,
    this.height,
    this.duration,
    this.numThumbnails,
    this.animatedPreview = false,
  });

  final String id;
  final String? type;
  final String? path;
  final String? name;
  final String? mime;
  final int? size;
  final int? width;
  final int? height;

  /// 秒
  final int? duration;
  final int? numThumbnails;
  final bool animatedPreview;

  static IwaraFile? fromJson(dynamic v) {
    final j = asJson(v);
    if (j == null || j['id'] == null) return null;
    return IwaraFile(
      id: j['id'].toString(),
      type: j['type'] as String?,
      path: j['path'] as String?,
      name: j['name'] as String?,
      mime: j['mime'] as String?,
      size: parseIntOrNull(j['size']),
      width: parseIntOrNull(j['width']),
      height: parseIntOrNull(j['height']),
      duration: parseIntOrNull(j['duration']),
      numThumbnails: parseIntOrNull(j['numThumbnails']),
      animatedPreview: j['animatedPreview'] == true,
    );
  }

  double? get aspectRatio =>
      (width ?? 0) > 0 && (height ?? 0) > 0 ? width! / height! : null;
}

class Tag {
  const Tag({required this.id, this.type, this.sensitive = false});

  final String id;
  final String? type;
  final bool sensitive;

  factory Tag.fromJson(Json j) => Tag(
        id: j['id'].toString(),
        type: j['type'] as String?,
        sensitive: j['sensitive'] == true,
      );
}
