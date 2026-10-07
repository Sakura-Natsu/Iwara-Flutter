import 'common.dart';
import 'user.dart';

class ForumSection {
  const ForumSection({
    required this.id,
    required this.group,
    this.locked = false,
    this.numPosts = 0,
    this.numThreads = 0,
    this.lastThread,
  });

  final String id;
  final String group;
  final bool locked;
  final int numPosts;
  final int numThreads;
  final ForumThread? lastThread;

  factory ForumSection.fromJson(Json j) {
    final lt = asJson(j['lastThread']);
    return ForumSection(
      id: j['id'].toString(),
      group: (j['group'] ?? '').toString(),
      locked: j['locked'] == true,
      numPosts: parseInt(j['numPosts']),
      numThreads: parseInt(j['numThreads']),
      lastThread: lt == null ? null : ForumThread.fromJson(lt),
    );
  }
}

class ForumThread {
  const ForumThread({
    required this.id,
    required this.title,
    required this.section,
    this.slug,
    this.locked = false,
    this.sticky = false,
    this.numViews = 0,
    this.numPosts = 0,
    this.user,
    this.lastPost,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String section;
  final String? slug;
  final bool locked;
  final bool sticky;
  final int numViews;
  final int numPosts;
  final User? user;
  final ForumPost? lastPost;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ForumThread.fromJson(Json j) {
    final lp = asJson(j['lastPost']);
    return ForumThread(
      id: j['id'].toString(),
      title: (j['title'] ?? '').toString(),
      section: (j['section'] ?? '').toString(),
      slug: j['slug'] as String?,
      locked: j['locked'] == true,
      sticky: j['sticky'] == true,
      numViews: parseInt(j['numViews']),
      numPosts: parseInt(j['numPosts']),
      user: User.maybe(j['user']),
      lastPost: lp == null ? null : ForumPost.fromJson(lp),
      createdAt: parseDate(j['createdAt']),
      updatedAt: parseDate(j['updatedAt']),
    );
  }
}

class ForumPost {
  const ForumPost({
    required this.id,
    required this.body,
    this.replyNum = 0,
    this.user,
    this.threadId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String body;

  /// 楼层号（从 0 开始）。
  final int replyNum;
  final User? user;
  final String? threadId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ForumPost.fromJson(Json j) => ForumPost(
        id: j['id'].toString(),
        body: (j['body'] ?? '').toString(),
        replyNum: parseInt(j['replyNum']),
        user: User.maybe(j['user']),
        threadId: j['threadId']?.toString(),
        createdAt: parseDate(j['createdAt']),
        updatedAt: parseDate(j['updatedAt']),
      );
}

/// 论坛论坛主题详情（一页楼层）。
class ForumThreadDetail {
  const ForumThreadDetail({
    required this.thread,
    required this.posts,
    this.count = 0,
    this.limit = 32,
    this.page = 0,
  });

  final ForumThread thread;
  final List<ForumPost> posts;
  final int count;
  final int limit;
  final int page;

  factory ForumThreadDetail.fromJson(Json j) => ForumThreadDetail(
        thread: ForumThread.fromJson(asJson(j['thread'])!),
        posts: parseList(j['results'], ForumPost.fromJson),
        count: parseInt(j['count']),
        limit: parseInt(j['limit'], 32),
        page: parseInt(j['page']),
      );
}

/// 验证码。
class Captcha {
  const Captcha({required this.id, required this.dataUri});

  final String id;

  /// data:image/png;base64,...
  final String dataUri;

  factory Captcha.fromJson(Json j) =>
      Captcha(id: j['id'].toString(), dataUri: (j['data'] ?? '').toString());
}

/// 板块中文名。
String forumSectionName(String id) {
  final base = id.replaceAll(RegExp(r'-(zh|ja)$'), '');
  return switch (base) {
    'announcements' => '公告',
    'feedback' => '反馈',
    'support' => '网站支持',
    'guides' => '指南',
    'general' => '综合讨论',
    'questions' => '帮助/问题',
    'requests' => '求物/请求',
    'sharing' => '分享',
    _ => id,
  };
}

String forumSectionDesc(String id) {
  final base = id.replaceAll(RegExp(r'-(zh|ja)$'), '');
  return switch (base) {
    'announcements' => '重要信息',
    'feedback' => '想法、建议和顾虑',
    'support' => '网站使用相关的问题',
    'guides' => '有用的信息和教程',
    'general' => '其他一切',
    'questions' => '与网站无关的问题',
    'requests' => '求模型、求视频、约稿',
    'sharing' => '分享你的作品和资源',
    _ => '',
  };
}

String forumGroupName(String group) => switch (group) {
      'administration' => '站务',
      'global' => '全球',
      'chinese' => '中文',
      'japanese' => '日本語',
      _ => group,
    };
