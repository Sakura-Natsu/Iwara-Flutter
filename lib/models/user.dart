import 'common.dart';

class User {
  const User({
    required this.id,
    required this.name,
    required this.username,
    this.role,
    this.status,
    this.avatar,
    this.premium = false,
    this.creatorProgram = false,
    this.following = false,
    this.followedBy = false,
    this.friend = false,
    this.seenAt,
    this.createdAt,
  });

  final String id;
  final String name;
  final String username;
  final String? role;
  final String? status;
  final IwaraFile? avatar;
  final bool premium;
  final bool creatorProgram;
  final bool following;
  final bool followedBy;
  final bool friend;
  final DateTime? seenAt;
  final DateTime? createdAt;

  static User? maybe(dynamic v) {
    final j = asJson(v);
    return j == null || j['id'] == null ? null : User.fromJson(j);
  }

  factory User.fromJson(Json j) => User(
        id: j['id'].toString(),
        name: (j['name'] ?? j['username'] ?? '').toString(),
        username: (j['username'] ?? '').toString(),
        role: j['role'] as String?,
        status: j['status'] as String?,
        avatar: IwaraFile.fromJson(j['avatar']),
        premium: j['premium'] == true,
        creatorProgram: j['creatorProgram'] == true,
        following: j['following'] == true,
        followedBy: j['followedBy'] == true,
        friend: j['friend'] == true,
        seenAt: parseDate(j['seenAt']),
        createdAt: parseDate(j['createdAt']),
      );

  User copyWith({bool? following, bool? friend}) => User(
        id: id,
        name: name,
        username: username,
        role: role,
        status: status,
        avatar: avatar,
        premium: premium,
        creatorProgram: creatorProgram,
        following: following ?? this.following,
        followedBy: followedBy,
        friend: friend ?? this.friend,
        seenAt: seenAt,
        createdAt: createdAt,
      );

  /// 5 分钟内活跃视为在线。
  bool get isOnline =>
      seenAt != null && DateTime.now().difference(seenAt!).inMinutes < 5;
}

/// 用户主页信息。
class Profile {
  const Profile({required this.user, this.body, this.header});

  final User user;
  final String? body;
  final IwaraFile? header;

  factory Profile.fromJson(Json j) => Profile(
        user: User.fromJson(asJson(j['user'])!),
        body: j['body'] as String?,
        header: IwaraFile.fromJson(j['header']),
      );

  Profile copyWith({User? user}) =>
      Profile(user: user ?? this.user, body: body, header: header);
}

/// 当前登录用户（GET /user）。
class CurrentUser {
  const CurrentUser({
    required this.user,
    this.email,
    this.tagBlacklist = const [],
    this.balance = 0,
  });

  final User user;
  final String? email;
  final List<String> tagBlacklist;
  final int balance;

  factory CurrentUser.fromJson(Json j) {
    final u = asJson(j['user']) ?? const {};
    return CurrentUser(
      user: User.fromJson(u),
      email: u['email'] as String?,
      tagBlacklist: (j['tagBlacklist'] as List? ?? const [])
          .map((e) => e is Map ? e['id'].toString() : e.toString())
          .toList(),
      balance: parseInt(j['balance']),
    );
  }
}

class UserCounts {
  const UserCounts({
    this.notifications = 0,
    this.messages = 0,
    this.friendRequests = 0,
  });

  final int notifications;
  final int messages;
  final int friendRequests;

  int get total => notifications + messages + friendRequests;

  factory UserCounts.fromJson(Json j) => UserCounts(
        notifications: parseInt(j['notifications']),
        messages: parseInt(j['messages']),
        friendRequests: parseInt(j['friendRequests']),
      );
}

/// 好友请求（user 为发起方，target 为接收方）。
class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.user,
    required this.target,
    this.createdAt,
  });

  final String id;
  final User user;
  final User target;
  final DateTime? createdAt;

  factory FriendRequest.fromJson(Json j) => FriendRequest(
        id: j['id'].toString(),
        user: User.fromJson(asJson(j['user'])!),
        target: User.fromJson(asJson(j['target'])!),
        createdAt: parseDate(j['createdAt']),
      );
}
