# 开发约定

欢迎贡献代码！提交 PR 前请先阅读本文与 [API.md](API.md)。

Flutter 3.44 / Dart 3.12，仅 Android。UI 文案一律**简体中文**。Material 3，主题跟随系统深浅色。

## 目录

```
lib/
  main.dart / app.dart / router.dart / providers.dart
  core/       constants.dart(SortType, Rating, kCategoryTags) settings.dart proxy.dart format.dart
  api/        api_client.dart  iwara_api.dart(IwaraApi，所有接口) urls.dart(IwaraUrls 图片/页面地址) api_exception.dart
  models/     common.dart(PageResult, IwaraFile, Tag, Json, parse*) user.dart video.dart image.dart social.dart forum.dart
  widgets/    paging.dart states.dart net_image.dart cards.dart rich_body.dart
  player/     播放器（PlayerView, IwaraPlayerController, fullscreen, pip）
  services/   local_db.dart download_service.dart
  pages/<feature>/...
docs/API.md   接口说明（逆向自官网前端）
```

## 状态与数据

- Riverpod 3（`flutter_riverpod`）。页面一般用 `ConsumerStatefulWidget` / `ConsumerWidget`。
- `ref.read(apiProvider)` → `IwaraApi`，所有网络请求都通过它，失败抛 `ApiException`（`message` 已是中文）。
- `ref.watch(meProvider)` → `CurrentUser?`（未登录为 null），`me.user.id` 为当前用户 id。
- `ref.watch(countsProvider)` → 未读计数 `UserCounts`；变更后可 `ref.invalidate(countsProvider)`。
- 不要新增全局 provider，除非确有必要；页面内状态放在 State 里即可。

## 通用组件（优先复用）

- 分页：`PagingController<T>(fetcher, dedupeKey:)` + `PagedView<T>(controller:, itemBuilder:, layout:, headerSlivers:)`。
  controller 在 State 中 `late final` 创建、`dispose()` 中释放；首次显示自动加载，自带下拉刷新、加载更多、空/错误状态。
  `layout`: `ListLayout(separated:)` 或 `GridLayout(...)`；视频网格用 `kVideoGridLayout`，图片网格用 `kImageGridLayout`（在 cards.dart）。
  修改列表项：`controller.updateWhere / removeWhere / insert / refresh`。
- 卡片：`VideoCard`（网格）、`VideoTile`（横向条目）、`ImageCard`、`PlaylistTile`、`R18Badge`（widgets/cards.dart）。
- 图片：`NetImage(url, fit:, borderRadius:, memCacheWidth:)`、`UserAvatar(user, size:, onTap:)`。
- 状态：`LoadingView`、`ErrorView.from(error, onRetry:)`、`EmptyView(text:, icon:)`。
- 反馈：`showToast(context, msg)`、`showError(context, error)`、`confirm(context, title, danger:)`、`promptText(context, title)`。
- 富文本：`RichBody(markdownText)` 渲染简介/评论/帖子；`openLink(context, url)` 站内链接走 App 路由。
- 评论：`CommentSection(type: ContentType.xxx, id:, ownerId:)`（pages/comments/comment_section.dart），自带输入栏和楼中楼。
  `requireLogin(context, ref)` 未登录时跳转登录页并返回 false；`showComposer(context, hint:)` 弹出多行输入框。
- 时间/数字：`formatAgo`、`formatDateTime`、`formatCount`、`formatSeconds`（core/format.dart）。
- 图片地址：`IwaraUrls.file('large'|'original'|'thumbnail'|'avatar'|'profileHeader', iwaraFile)`、`IwaraUrls.imageThumbnail(img)`、`IwaraUrls.videoThumbnail(video)`、`IwaraUrls.xxxPage(id)`（网页地址，用于分享/浏览器打开）。

## 路由（go_router，见 router.dart）

`context.push(...)` 跳转：
`/video/:id`(extra: Video) `/image/:id`(extra: GalleryImage) `/profile/:username` `/user/:userId/follows?tab=followers|following&name=`
`/user/:userId/playlists?name=` `/playlist/:id` `/post/:id` `/search?type=videos|images|users|posts|playlists|forum_threads&q=`
`/login` `/settings` `/favorites` `/history` `/downloads` `/notifications` `/messages` `/messages/:id`(extra: Conversation) `/friends`
`/forum` `/forum/:section` `/forum/:section/:threadId`

## 规范

- 新增页面时在 `router.dart` 注册路由，页面构造参数与路由解析保持一致。
- 需要登录的操作先 `requireLogin`；乐观更新 UI，失败只回滚对应字段并 `showError`。
- 新接口统一加到 `lib/api/iwara_api.dart`，并在 `docs/API.md` 记录（接口为逆向所得，注明验证情况）。
- 用到 `BuildContext` 的异步回调先检查 `mounted` / `context.mounted`。
- 提交前运行 `flutter analyze`，需 0 error / 0 warning（CI 会检查）。
- 不要在代码、截图或 Issue 中提交任何账号凭据、token 或个人信息。
