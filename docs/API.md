# Iwara API 笔记

逆向自 www.iwara.tv 前端（ver. 3.3.7，2026-10），可能随官方更新变化。

## 基础

- API 根：`https://api.iwara.tv/`
- 请求头：
  - `Authorization: Bearer <accessToken>`（登录后）
  - `X-Site: www.iwara.tv`
  - `X-Captcha: <captchaId>:<answer>`（论坛发帖/回帖、动态发布等需要）
- Cloudflare：curl 默认 UA 会被 403，`Dart/x.y (dart:io)` UA 正常。
- 分页返回：`{ count, limit, page, results: [...] }`，`page` 从 0 开始。

## 鉴权

| 操作 | 请求 |
| --- | --- |
| 登录 | `POST user/login` `{email, password}`（email 字段可填邮箱或用户名） → `{token}`（refresh token，JWT） |
| 换取 access token | `POST user/token`（Bearer refresh token）→ `{accessToken}` |
| 当前用户 | `GET user` → `{user, profile, tagBlacklist, balance, notifications}` |
| 未读计数 | `GET user/counts` → `{notifications, messages, friendRequests}` |

## 视频

- 列表 `GET videos?sort=&rating=&tags=&date=&page=&limit=&user=&subscribed=true&exclude=`
  - sort: `date` `trending` `popularity` `views` `likes`
  - rating: `all` `general` `ecchi`
- 热门 `GET trending/video?rating=&limit=`
- 详情 `GET video/{id}` → 含 `file`、`fileUrl`、`liked`、`user`、`tags`、`embedUrl`(YouTube 等外链视频)
- 相关 `GET video/{id}/related`
- 点赞/收藏 `POST|DELETE video/{id}/like`（收藏夹 = 点赞列表）
- 观看上报 `POST video/{id}/view`
- 播放地址：
  1. `fileUrl` 形如 `https://files*.iwara.tv/file/{fileId}?expires=...&hash=...`
  2. `X-Version = sha1("{file.id}_{expires}_{salt}")`，salt 当前为 `mSvL05GfEmeEmsEYfGCnVpEjYgTJraJN`（写在前端 main.js 中，搜 `X-Version`）
  3. `GET fileUrl` 带 `X-Version` → `[{name: Source|540|360|preview, type, src: {view, download}}]`，src 为 `//host/view?...` 协议相对地址

## 图片

- 列表 `GET images?sort=&rating=&tags=&page=&user=&subscribed=true`
- 详情 `GET image/{id}` → `files[]`
- 点赞 `POST|DELETE image/{id}/like`

## 图片 URL（i.iwara.tv）

- `//i.iwara.tv/image/{size}/{file.id}/{file.name}`，size ≠ `original` 时扩展名替换为 `.jpg`
  - size: `thumbnail` `large` `original` `avatar` `profileHeader`
- 视频缩略图：`/image/thumbnail/{file.id}/thumbnail-{NN}.jpg`（NN = `video.thumbnail` 两位补零）；有 `customThumbnail` 时用其文件
- 动态预览：`/image/original/{file.id}/preview.webp`（`file.animatedPreview == true`）
- 外链视频缩略图：`/image/embed/{size}/{provider}/{id}`

## 评论

- `GET {type}/{id}/comments?page=&parent={commentId}`，type: `video` `image` `profile` `post`
- `POST {type}/{id}/comments` `{body}`（回复时 `{body, parentId}`）
- `PUT comment/{id}`、`DELETE comment/{id}`

## 用户

- `GET profile/{username}` → `{user, body, header, ...}`
- `POST|DELETE user/{id}/followers` 关注/取关
- `GET user/{id}/followers`、`GET user/{id}/following`
- 好友：`GET user/{id}/friends`、`GET user/{id}/friends/requests`、`POST user/{id}/friends`（申请/接受）、`DELETE user/{id}/friends`、`GET user/{id}/friends/status`
- 屏蔽：`POST|DELETE user/{id}/block`
- 历史：`GET user/{id}/history/{video|image}`

## 播放列表

- `GET playlists?user={id}`、`GET playlist/{id}`
- `GET light/playlists?id={videoId}`（当前用户的播放列表简表）
- `POST playlists` `{title}`、`PUT|DELETE playlist/{id}`
- `POST|DELETE playlist/{playlistId}/{videoId}`

## 收藏 / 订阅

- `GET favorites/videos`、`GET favorites/images` → `results[].video|image`
- 订阅流：`GET videos?subscribed=true`、`GET images?subscribed=true`

## 搜索

- `GET search?type={videos|images|users|posts|playlists|forum_posts|forum_threads}&query=&page=`
- 标签补全 `GET autocomplete/tags?query=`

## 通知 / 私信

- `GET user/{id}/notifications` → `results[]{id, type, read, comment, video|image|profile|post, tag, createdAt}`
  - type: `newComment` `newReply` `videoReady` `warning` `tagApproved` `joinedCreatorProgram` `reviewApproved` `reviewRejected`
- `POST notifications/{id}/read`
- `GET user/{id}/conversations` → `results[]{id, title, participants[], unread, updatedAt}`
- `POST user/{recipientId}/conversations` `{user, title, body}`
- `GET conversation/{id}/messages`、`POST conversation/{id}/messages` `{body}`、`DELETE message/{id}`

## 论坛

- `GET forum` → 板块数组 `{id, group, locked, numPosts, numThreads, lastThread}`
- `GET forum/{sectionId}?page=` → 主题列表
- `GET forum/{sectionId}/{threadId}?page=` → `{thread, results(posts)}`
- `POST forum/{threadId}/reply` `{body}` + `X-Captcha`
- 验证码 `GET captcha` → `{id, data: "data:image/png;base64,..."}`，约 110 秒过期

## 动态 Posts

- `GET posts?user={id}`、`GET post/{id}`
