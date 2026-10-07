import 'common.dart';
import 'user.dart';

class Video {
  const Video({
    required this.id,
    required this.title,
    this.slug,
    this.body,
    this.status,
    this.rating,
    this.isPrivate = false,
    this.unlisted = false,
    this.thumbnail = 0,
    this.embedUrl,
    this.liked = false,
    this.numLikes = 0,
    this.numViews = 0,
    this.numComments = 0,
    this.file,
    this.customThumbnail,
    this.user,
    this.tags = const [],
    this.createdAt,
    this.updatedAt,
    this.fileUrl,
  });

  final String id;
  final String title;
  final String? slug;
  final String? body;
  final String? status;
  final String? rating;
  final bool isPrivate;
  final bool unlisted;
  final int thumbnail;
  final String? embedUrl;
  final bool liked;
  final int numLikes;
  final int numViews;
  final int numComments;
  final IwaraFile? file;
  final IwaraFile? customThumbnail;
  final User? user;
  final List<Tag> tags;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 仅详情接口返回，用于获取播放直链。
  final String? fileUrl;

  bool get isR18 => rating == 'ecchi';
  bool get isExternal => file == null && embedUrl != null;
  int? get durationSeconds => file?.duration;

  static Video? maybe(dynamic v) {
    final j = asJson(v);
    return j == null || j['id'] == null ? null : Video.fromJson(j);
  }

  factory Video.fromJson(Json j) => Video(
        id: j['id'].toString(),
        title: (j['title'] ?? '').toString(),
        slug: j['slug'] as String?,
        body: j['body'] as String?,
        status: j['status'] as String?,
        rating: j['rating'] as String?,
        isPrivate: j['private'] == true,
        unlisted: j['unlisted'] == true,
        thumbnail: parseInt(j['thumbnail']),
        embedUrl: j['embedUrl'] as String?,
        liked: j['liked'] == true,
        numLikes: parseInt(j['numLikes']),
        numViews: parseInt(j['numViews']),
        numComments: parseInt(j['numComments']),
        file: IwaraFile.fromJson(j['file']),
        customThumbnail: IwaraFile.fromJson(j['customThumbnail']),
        user: User.maybe(j['user']),
        tags: parseList(j['tags'], Tag.fromJson),
        createdAt: parseDate(j['createdAt']),
        updatedAt: parseDate(j['updatedAt']),
        fileUrl: j['fileUrl'] as String?,
      );

  Video copyWith({bool? liked, int? numLikes, User? user}) => Video(
        id: id,
        title: title,
        slug: slug,
        body: body,
        status: status,
        rating: rating,
        isPrivate: isPrivate,
        unlisted: unlisted,
        thumbnail: thumbnail,
        embedUrl: embedUrl,
        liked: liked ?? this.liked,
        numLikes: numLikes ?? this.numLikes,
        numViews: numViews,
        numComments: numComments,
        file: file,
        customThumbnail: customThumbnail,
        user: user ?? this.user,
        tags: tags,
        createdAt: createdAt,
        updatedAt: updatedAt,
        fileUrl: fileUrl,
      );
}

/// 某个清晰度的播放源。
class VideoSource {
  const VideoSource({
    required this.name,
    required this.viewUrl,
    required this.downloadUrl,
    this.type,
  });

  /// Source / 540 / 360 / preview
  final String name;
  final String viewUrl;
  final String downloadUrl;
  final String? type;

  String get label => switch (name) {
        'Source' => '原画',
        'preview' => '预览',
        _ => '${name}P',
      };

  static String _abs(String? u) {
    if (u == null || u.isEmpty) return '';
    return u.startsWith('//') ? 'https:$u' : u;
  }

  factory VideoSource.fromJson(Json j) {
    final src = asJson(j['src']) ?? const {};
    return VideoSource(
      name: (j['name'] ?? '').toString(),
      type: j['type'] as String?,
      viewUrl: _abs(src['view'] as String?),
      downloadUrl: _abs(src['download'] as String?),
    );
  }
}
