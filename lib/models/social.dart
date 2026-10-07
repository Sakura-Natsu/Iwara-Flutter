import 'common.dart';
import 'image.dart';
import 'user.dart';
import 'video.dart';

class Comment {
  const Comment({
    required this.id,
    required this.body,
    this.numReplies = 0,
    this.parentId,
    this.user,
    this.createdAt,
    this.updatedAt,
    this.approved = true,
  });

  final String id;
  final String body;
  final int numReplies;
  final String? parentId;
  final User? user;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool approved;

  bool get edited =>
      createdAt != null &&
      updatedAt != null &&
      updatedAt!.difference(createdAt!).inSeconds > 5;

  factory Comment.fromJson(Json j) {
    final parent = j['parent'];
    return Comment(
      id: j['id'].toString(),
      body: (j['body'] ?? '').toString(),
      numReplies: parseInt(j['numReplies']),
      parentId: parent is Map ? parent['id']?.toString() : parent?.toString(),
      user: User.maybe(j['user']),
      createdAt: parseDate(j['createdAt']),
      updatedAt: parseDate(j['updatedAt']),
      approved: j['approved'] != false,
    );
  }
}

class Playlist {
  const Playlist({
    required this.id,
    required this.title,
    this.numVideos = 0,
    this.user,
    this.thumbnailVideo,
  });

  final String id;
  final String title;
  final int numVideos;
  final User? user;

  /// 封面：接口返回 `{file, thumbnail}`，结构与视频一致。
  final Video? thumbnailVideo;

  factory Playlist.fromJson(Json j) {
    final thumb = asJson(j['thumbnail']);
    return Playlist(
      id: j['id'].toString(),
      title: (j['title'] ?? '').toString(),
      numVideos: parseInt(j['numVideos']),
      user: User.maybe(j['user']),
      thumbnailVideo: thumb == null
          ? null
          : Video.fromJson({...thumb, 'id': thumb['id'] ?? '', 'title': ''}),
    );
  }
}

/// `light/playlists?id=videoId` 返回的简表。
class LightPlaylist {
  const LightPlaylist({
    required this.id,
    required this.title,
    this.numVideos = 0,
    this.added = false,
  });

  final String id;
  final String title;
  final int numVideos;
  final bool added;

  factory LightPlaylist.fromJson(Json j) => LightPlaylist(
        id: j['id'].toString(),
        title: (j['title'] ?? '').toString(),
        numVideos: parseInt(j['numVideos']),
        added: j['added'] == true,
      );

  LightPlaylist copyWith({bool? added, int? numVideos}) => LightPlaylist(
        id: id,
        title: title,
        numVideos: numVideos ?? this.numVideos,
        added: added ?? this.added,
      );
}

/// 用户动态。
class Post {
  const Post({
    required this.id,
    required this.title,
    this.body,
    this.numViews = 0,
    this.user,
    this.createdAt,
  });

  final String id;
  final String title;
  final String? body;
  final int numViews;
  final User? user;
  final DateTime? createdAt;

  factory Post.fromJson(Json j) => Post(
        id: j['id'].toString(),
        title: (j['title'] ?? '').toString(),
        body: j['body'] as String?,
        numViews: parseInt(j['numViews']),
        user: User.maybe(j['user']),
        createdAt: parseDate(j['createdAt']),
      );
}

class IwaraNotification {
  const IwaraNotification({
    required this.id,
    required this.type,
    this.read = false,
    this.comment,
    this.video,
    this.image,
    this.profileUser,
    this.post,
    this.tagId,
    this.createdAt,
  });

  final String id;
  final String type;
  final bool read;
  final Comment? comment;
  final Video? video;
  final GalleryImage? image;
  final User? profileUser;
  final Post? post;
  final String? tagId;
  final DateTime? createdAt;

  factory IwaraNotification.fromJson(Json j) => IwaraNotification(
        id: j['id'].toString(),
        type: (j['type'] ?? '').toString(),
        read: j['read'] == true,
        comment: asJson(j['comment']) == null
            ? null
            : Comment.fromJson(asJson(j['comment'])!),
        video: Video.maybe(j['video']),
        image: GalleryImage.maybe(j['image']),
        profileUser: User.maybe(j['profile']),
        post: asJson(j['post']) == null ? null : Post.fromJson(asJson(j['post'])!),
        tagId: asJson(j['tag'])?['id']?.toString(),
        createdAt: parseDate(j['createdAt']),
      );

  IwaraNotification markRead() => IwaraNotification(
        id: id,
        type: type,
        read: true,
        comment: comment,
        video: video,
        image: image,
        profileUser: profileUser,
        post: post,
        tagId: tagId,
        createdAt: createdAt,
      );
}

class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    this.participants = const [],
    this.unread = false,
    this.updatedAt,
  });

  final String id;
  final String title;
  final List<User> participants;
  final bool unread;
  final DateTime? updatedAt;

  User? otherParticipant(String? myId) {
    if (participants.isEmpty) return null;
    return participants.firstWhere((u) => u.id != myId,
        orElse: () => participants.first);
  }

  factory Conversation.fromJson(Json j) => Conversation(
        id: j['id'].toString(),
        title: (j['title'] ?? '').toString(),
        participants: parseList(j['participants'], User.fromJson),
        unread: j['unread'] == true,
        updatedAt: parseDate(j['updatedAt']),
      );
}

class Message {
  const Message({
    required this.id,
    required this.body,
    this.user,
    this.createdAt,
  });

  final String id;
  final String body;
  final User? user;
  final DateTime? createdAt;

  factory Message.fromJson(Json j) => Message(
        id: j['id'].toString(),
        body: (j['body'] ?? '').toString(),
        user: User.maybe(j['user']),
        createdAt: parseDate(j['createdAt']),
      );
}

/// 观看历史条目。
class HistoryEntry {
  const HistoryEntry({required this.type, this.video, this.image, this.createdAt});

  final String type;
  final Video? video;
  final GalleryImage? image;
  final DateTime? createdAt;

  factory HistoryEntry.fromJson(Json j) {
    final type = (j['type'] ?? '').toString();
    return HistoryEntry(
      type: type,
      video: type == 'video' ? Video.maybe(j['content']) : null,
      image: type == 'image' ? GalleryImage.maybe(j['content']) : null,
      createdAt: parseDate(j['createdAt']),
    );
  }
}
