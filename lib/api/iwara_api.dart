import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'dart:convert';

import '../core/constants.dart';
import '../models/common.dart';
import '../models/forum.dart';
import '../models/image.dart';
import '../models/social.dart';
import '../models/user.dart';
import '../models/video.dart';
import 'api_client.dart';
import 'api_exception.dart';

/// 评论/点赞等接口通用的内容类型。
enum ContentType {
  video('video'),
  image('image'),
  profile('profile'),
  post('post');

  const ContentType(this.path);
  final String path;
}

class IwaraApi {
  IwaraApi(this.client, {required this.saltProvider, required this.onSaltUpdated});

  final ApiClient client;

  /// 当前签名盐值。
  final String Function() saltProvider;
  final void Function(String salt) onSaltUpdated;

  Json _j(dynamic v) => asJson(v) ?? <String, dynamic>{};

  // ---------------- 账号 ----------------

  /// [account] 可以是邮箱或用户名（接口字段名为 email）。
  Future<void> login(String account, String password) async {
    final res = await client.post<Map<String, dynamic>>('user/login',
        data: {'email': account, 'password': password}, noAuth: true);
    final token = res['token'] as String?;
    if (token == null) throw ApiException('登录失败：未返回令牌');
    await client.setRefreshToken(token);
  }

  Future<CurrentUser> currentUser() async =>
      CurrentUser.fromJson(_j(await client.get('user')));

  Future<UserCounts> counts() async =>
      UserCounts.fromJson(_j(await client.get('user/counts')));

  // ---------------- 视频 ----------------

  Future<PageResult<Video>> videos({
    String? sort,
    Rating rating = Rating.all,
    int page = 0,
    int limit = IwaraConst.pageSize,
    List<String>? tags,
    String? date,
    String? userId,
    bool subscribed = false,
    String? exclude,
  }) async {
    final j = _j(await client.get('videos', query: {
      'sort': sort,
      'rating': rating.value,
      'page': page,
      'limit': limit,
      'tags': tags == null || tags.isEmpty ? null : tags.join(','),
      'date': date,
      'user': userId,
      'subscribed': subscribed ? 'true' : null,
      'exclude': exclude,
    }));
    return PageResult.fromJson(j, Video.fromJson);
  }

  Future<Video> video(String id) async =>
      Video.fromJson(_j(await client.get('video/$id')));

  Future<List<Video>> relatedVideos(String id) async {
    final j = _j(await client.get('video/$id/related'));
    return parseList(j['results'], Video.fromJson);
  }

  Future<void> sendView(ContentType type, String id) =>
      client.post('${type.path}/$id/view');

  /// 解析播放源。签名失败时自动尝试从官网前端更新盐值后重试一次。
  Future<List<VideoSource>> videoSources(Video video) async {
    final fileUrl = video.fileUrl;
    final fileId = video.file?.id;
    if (fileUrl == null || fileId == null) {
      throw ApiException('该视频没有可播放的文件');
    }
    try {
      return await _fetchSources(fileUrl, fileId, saltProvider());
    } on ApiException catch (e) {
      if (e.status != 403 && e.status != 401 && e.status != 400) rethrow;
      final salt = await fetchSaltFromSite();
      if (salt == null || salt == saltProvider()) rethrow;
      onSaltUpdated(salt);
      return _fetchSources(fileUrl, fileId, salt);
    }
  }

  Future<List<VideoSource>> _fetchSources(
      String fileUrl, String fileId, String salt) async {
    final uri = Uri.parse(fileUrl);
    final expires = uri.queryParameters['expires'] ?? '';
    final xVersion =
        sha1.convert(utf8.encode('${fileId}_${expires}_$salt')).toString();
    try {
      final token = await client.accessToken();
      final res = await client.dio.getUri<List<dynamic>>(
        uri,
        options: Options(
          headers: {
            'X-Version': xVersion,
            if (token != null) 'Authorization': 'Bearer $token',
          },
          extra: {'noAuth': true},
        ),
      );
      final list = (res.data ?? const [])
          .whereType<Map>()
          .map((e) => VideoSource.fromJson(e.cast<String, dynamic>()))
          .where((s) => s.viewUrl.isNotEmpty)
          .toList();
      if (list.isEmpty) throw ApiException('没有可用的播放源');
      // 按清晰度从高到低：Source > 数字分辨率 > preview
      int rank(String n) => switch (n) {
            'Source' => 1 << 20,
            'preview' => -1,
            _ => int.tryParse(n) ?? 0,
          };
      list.sort((a, b) => rank(b.name).compareTo(rank(a.name)));
      return list;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// 从官网 main.js 中提取 X-Version 盐值。
  Future<String?> fetchSaltFromSite() async {
    try {
      final html = await client.dio.get<String>(IwaraConst.siteUrl,
          options: Options(responseType: ResponseType.plain, extra: {'noAuth': true}));
      final m = RegExp(r'src="(/main\.[0-9a-f]+\.js)"').firstMatch(html.data ?? '');
      if (m == null) return null;
      final js = await client.dio.get<String>('${IwaraConst.siteUrl}${m.group(1)}',
          options: Options(responseType: ResponseType.plain, extra: {'noAuth': true}));
      final s = RegExp(r'"_"\+[a-zA-Z.]+expires\+"_([A-Za-z0-9]{16,})"')
          .firstMatch(js.data ?? '');
      return s?.group(1);
    } catch (_) {
      return null;
    }
  }

  // ---------------- 图片 ----------------

  Future<PageResult<GalleryImage>> images({
    String? sort,
    Rating rating = Rating.all,
    int page = 0,
    int limit = IwaraConst.pageSize,
    List<String>? tags,
    String? date,
    String? userId,
    bool subscribed = false,
    String? exclude,
  }) async {
    final j = _j(await client.get('images', query: {
      'sort': sort,
      'rating': rating.value,
      'page': page,
      'limit': limit,
      'tags': tags == null || tags.isEmpty ? null : tags.join(','),
      'date': date,
      'user': userId,
      'subscribed': subscribed ? 'true' : null,
      'exclude': exclude,
    }));
    return PageResult.fromJson(j, GalleryImage.fromJson);
  }

  Future<GalleryImage> image(String id) async =>
      GalleryImage.fromJson(_j(await client.get('image/$id')));

  Future<List<GalleryImage>> relatedImages(String id) async {
    final j = _j(await client.get('image/$id/related'));
    return parseList(j['results'], GalleryImage.fromJson);
  }

  // ---------------- 点赞 / 收藏 ----------------

  Future<void> like(ContentType type, String id) =>
      client.post('${type.path}/$id/like');

  Future<void> unlike(ContentType type, String id) =>
      client.delete('${type.path}/$id/like');

  Future<PageResult<Video>> favoriteVideos({int page = 0}) async {
    final j = _j(await client.get('favorites/videos',
        query: {'page': page, 'limit': IwaraConst.pageSize}));
    return PageResult.fromJson(j, (e) => Video.fromJson(_j(e['video'])));
  }

  Future<PageResult<GalleryImage>> favoriteImages({int page = 0}) async {
    final j = _j(await client.get('favorites/images',
        query: {'page': page, 'limit': IwaraConst.pageSize}));
    return PageResult.fromJson(j, (e) => GalleryImage.fromJson(_j(e['image'])));
  }

  // ---------------- 评论 ----------------

  Future<PageResult<Comment>> comments(ContentType type, String id,
      {int page = 0, String? parentId}) async {
    final j = _j(await client.get('${type.path}/$id/comments',
        query: {'page': page, 'parent': parentId}));
    return PageResult.fromJson(j, Comment.fromJson);
  }

  Future<Comment?> createComment(ContentType type, String id, String body,
      {String? parentId}) async {
    final data = parentId == null
        ? {'body': body, 'rulesAgreement': true}
        : {'body': body, 'parentId': parentId};
    final res = await client.post('${type.path}/$id/comments', data: data);
    final j = asJson(res);
    return j == null || j['id'] == null ? null : Comment.fromJson(j);
  }

  Future<void> updateComment(String id, String body) =>
      client.put('comment/$id', data: {'body': body});

  Future<void> deleteComment(String id) => client.delete('comment/$id');

  // ---------------- 用户 ----------------

  Future<Profile> profile(String username) async =>
      Profile.fromJson(_j(await client.get('profile/$username')));

  Future<void> follow(String userId) => client.post('user/$userId/followers');
  Future<void> unfollow(String userId) =>
      client.delete('user/$userId/followers');

  Future<PageResult<User>> followers(String userId, {int page = 0}) async {
    final j = _j(await client.get('user/$userId/followers',
        query: {'page': page, 'limit': IwaraConst.pageSize}));
    return PageResult.fromJson(j, (e) => User.fromJson(_j(e['follower'])));
  }

  Future<PageResult<User>> following(String userId, {int page = 0}) async {
    final j = _j(await client.get('user/$userId/following',
        query: {'page': page, 'limit': IwaraConst.pageSize}));
    return PageResult.fromJson(j, (e) => User.fromJson(_j(e['user'])));
  }

  Future<PageResult<User>> friends(String userId, {int page = 0}) async {
    final j = _j(await client.get('user/$userId/friends',
        query: {'page': page, 'limit': IwaraConst.pageSize}));
    return PageResult.fromJson(j, User.fromJson);
  }

  Future<PageResult<FriendRequest>> friendRequests(String userId,
      {int page = 0}) async {
    final j = _j(await client.get('user/$userId/friends/requests',
        query: {'page': page}));
    return PageResult.fromJson(j, FriendRequest.fromJson);
  }

  /// 发送好友请求 / 接受对方请求。
  Future<void> addFriend(String userId) => client.post('user/$userId/friends');

  /// 删除好友 / 拒绝或撤回请求。
  Future<void> removeFriend(String userId) =>
      client.delete('user/$userId/friends');

  /// 返回 none / friends / pending 等。
  Future<String> friendStatus(String userId) async {
    final j = _j(await client.get('user/$userId/friends/status'));
    return (j['status'] ?? 'none').toString();
  }

  Future<void> blockUser(String userId) => client.post('user/$userId/block');
  Future<void> unblockUser(String userId) =>
      client.delete('user/$userId/block');

  Future<PageResult<HistoryEntry>> history(String userId, String type,
      {int page = 0}) async {
    final j = _j(await client.get('user/$userId/history/$type',
        query: {'page': page, 'limit': IwaraConst.pageSize}));
    return PageResult.fromJson(j, HistoryEntry.fromJson);
  }

  Future<PageResult<Post>> posts({String? userId, int page = 0}) async {
    final j = _j(await client.get('posts',
        query: {'user': userId, 'page': page, 'limit': IwaraConst.pageSize}));
    return PageResult.fromJson(j, Post.fromJson);
  }

  Future<Post> post(String id) async =>
      Post.fromJson(_j(await client.get('post/$id')));

  // ---------------- 播放列表 ----------------

  Future<PageResult<Playlist>> playlists(String userId, {int page = 0}) async {
    final j = _j(await client.get('playlists',
        query: {'user': userId, 'page': page, 'limit': IwaraConst.pageSize}));
    return PageResult.fromJson(j, Playlist.fromJson);
  }

  /// 返回 (播放列表信息, 视频分页)。
  Future<(Playlist, PageResult<Video>)> playlist(String id,
      {int page = 0}) async {
    final j = _j(await client.get('playlist/$id', query: {'page': page}));
    return (
      Playlist.fromJson(_j(j['playlist'])),
      PageResult.fromJson(j, Video.fromJson),
    );
  }

  Future<List<LightPlaylist>> lightPlaylists(String videoId) async {
    final res = await client.get('light/playlists', query: {'id': videoId});
    return parseList(res, LightPlaylist.fromJson);
  }

  Future<void> createPlaylist(String title) =>
      client.post('playlists', data: {'title': title});

  Future<void> renamePlaylist(String id, String title) =>
      client.put('playlist/$id', data: {'title': title});

  Future<void> deletePlaylist(String id) => client.delete('playlist/$id');

  Future<void> addToPlaylist(String playlistId, String videoId) =>
      client.post('playlist/$playlistId/$videoId');

  Future<void> removeFromPlaylist(String playlistId, String videoId) =>
      client.delete('playlist/$playlistId/$videoId');

  // ---------------- 搜索 ----------------

  Future<PageResult<T>> search<T>(
      String type, String query, T Function(Json) parse,
      {int page = 0}) async {
    final j = _j(await client.get('search',
        query: {'type': type, 'query': query, 'page': page}));
    return PageResult.fromJson(j, parse);
  }

  Future<List<Tag>> autocompleteTags(String query) async {
    final j = _j(await client.get('autocomplete/tags', query: {'query': query}));
    return parseList(j['results'], Tag.fromJson);
  }

  // ---------------- 通知 / 私信 ----------------

  Future<PageResult<IwaraNotification>> notifications(String userId,
      {int page = 0}) async {
    final j = _j(await client.get('user/$userId/notifications',
        query: {'page': page}));
    return PageResult.fromJson(j, IwaraNotification.fromJson);
  }

  Future<void> markNotificationRead(String id) =>
      client.post('notifications/$id/read');

  Future<PageResult<Conversation>> conversations(String userId,
      {int page = 0}) async {
    final j = _j(await client.get('user/$userId/conversations',
        query: {'page': page}));
    return PageResult.fromJson(j, Conversation.fromJson);
  }

  /// 消息列表，before 为分页游标（更早的消息）。
  Future<PageResult<Message>> messages(String conversationId,
      {int page = 0}) async {
    final j = _j(await client.get('conversation/$conversationId/messages',
        query: {'page': page}));
    return PageResult.fromJson(j, Message.fromJson);
  }

  Future<Message?> sendMessage(String conversationId, String body) async {
    final res = await client
        .post('conversation/$conversationId/messages', data: {'body': body});
    final j = asJson(res);
    return j == null || j['id'] == null ? null : Message.fromJson(j);
  }

  Future<void> deleteMessage(String id) => client.delete('message/$id');

  /// 创建会话，返回会话 id。
  Future<String?> createConversation(
      String recipientId, String title, String body) async {
    final res = await client.post('user/$recipientId/conversations',
        data: {'user': recipientId, 'title': title, 'body': body});
    return asJson(res)?['id']?.toString();
  }

  // ---------------- 论坛 ----------------

  Future<List<ForumSection>> forumSections() async =>
      parseList(await client.get('forum'), ForumSection.fromJson);

  Future<PageResult<ForumThread>> forumThreads(String section,
      {int page = 0}) async {
    final j = _j(await client.get('forum/$section', query: {'page': page}));
    return PageResult.fromJson(j, ForumThread.fromJson, key: 'threads');
  }

  Future<ForumThreadDetail> forumThread(String section, String threadId,
      {int page = 0}) async {
    final j = _j(
        await client.get('forum/$section/$threadId', query: {'page': page}));
    return ForumThreadDetail.fromJson(j);
  }

  Future<Captcha> captcha() async =>
      Captcha.fromJson(_j(await client.get('captcha')));

  Future<void> replyForumThread(String threadId, String body,
          {required String captchaId, required String captchaAnswer}) =>
      client.post('forum/$threadId/reply',
          data: {'body': body, 'rulesAgreement': true},
          headers: {'X-Captcha': '$captchaId:$captchaAnswer'});
}
