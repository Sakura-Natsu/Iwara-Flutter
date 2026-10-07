import 'common.dart';
import 'user.dart';

/// 图片/图集。
class GalleryImage {
  const GalleryImage({
    required this.id,
    required this.title,
    this.body,
    this.thumbnail,
    this.rating,
    this.liked = false,
    this.numImages = 0,
    this.numLikes = 0,
    this.numViews = 0,
    this.numComments = 0,
    this.files = const [],
    this.tags = const [],
    this.user,
    this.createdAt,
  });

  final String id;
  final String title;
  final String? body;
  final IwaraFile? thumbnail;
  final String? rating;
  final bool liked;
  final int numImages;
  final int numLikes;
  final int numViews;
  final int numComments;
  final List<IwaraFile> files;
  final List<Tag> tags;
  final User? user;
  final DateTime? createdAt;

  bool get isR18 => rating == 'ecchi';

  static GalleryImage? maybe(dynamic v) {
    final j = asJson(v);
    return j == null || j['id'] == null ? null : GalleryImage.fromJson(j);
  }

  factory GalleryImage.fromJson(Json j) => GalleryImage(
        id: j['id'].toString(),
        title: (j['title'] ?? '').toString(),
        body: j['body'] as String?,
        thumbnail: IwaraFile.fromJson(j['thumbnail']),
        rating: j['rating'] as String?,
        liked: j['liked'] == true,
        numImages: parseInt(j['numImages']),
        numLikes: parseInt(j['numLikes']),
        numViews: parseInt(j['numViews']),
        numComments: parseInt(j['numComments']),
        files: (j['files'] as List? ?? const [])
            .map(IwaraFile.fromJson)
            .whereType<IwaraFile>()
            .toList(),
        tags: parseList(j['tags'], Tag.fromJson),
        user: User.maybe(j['user']),
        createdAt: parseDate(j['createdAt']),
      );

  GalleryImage copyWith({bool? liked, int? numLikes, User? user}) =>
      GalleryImage(
        id: id,
        title: title,
        body: body,
        thumbnail: thumbnail,
        rating: rating,
        liked: liked ?? this.liked,
        numImages: numImages,
        numLikes: numLikes ?? this.numLikes,
        numViews: numViews,
        numComments: numComments,
        files: files,
        tags: tags,
        user: user ?? this.user,
        createdAt: createdAt,
      );
}
