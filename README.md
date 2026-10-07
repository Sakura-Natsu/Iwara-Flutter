<p align="center">
  <img src="assets/icon/icon.png" width="128" alt="Iwara Flutter">
</p>

<h1 align="center">Iwara Flutter</h1>

<p align="center">
  <a href="https://www.iwara.tv">iwara.tv</a> 的第三方 Android 原生客户端（非官方）
</p>

<p align="center">
  <a href="https://github.com/Sakura-Natsu/Iwara-Flutter/releases"><img src="https://img.shields.io/github/v/release/Sakura-Natsu/Iwara-Flutter?label=%E4%B8%8B%E8%BD%BD" alt="Release"></a>
  <img src="https://img.shields.io/badge/platform-Android%207.0%2B-3DDC84?logo=android&logoColor=white" alt="Android">
  <img src="https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter" alt="Flutter">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="GPL-3.0"></a>
</p>

> [!WARNING]
> - 本项目是**非官方**客户端，与 Iwara 官方无任何关联。
> - Iwara 包含成人内容，请确认你已年满 18 周岁，并遵守所在地法律法规及网站服务条款。
> - 本应用仅调用网站公开接口展示内容，不存储、不分发任何视频或图片。

## ✨ 功能

**浏览**
- 视频：流行 / 最新 / 人气 / 最多观看 / 最多赞排序，按分级、分类标签、年月筛选
- 图片 / 图集：多图翻页、全屏缩放查看、保存原图到相册
- 论坛：板块、主题、楼层浏览，带验证码回帖
- 用户主页：视频、图片、动态、播放列表、留言板，关注 / 粉丝列表
- 搜索：视频、图片、用户、动态、播放列表、论坛主题，保留搜索历史

**播放**（基于 [media_kit](https://github.com/media-kit/media-kit) / libmpv）
- 原画 / 540P / 360P 切换、倍速、长按倍速
- 手势：左右滑动调进度、左侧亮度、右侧音量、双击暂停
- 全屏（按视频方向自动横竖屏）、锁定、循环播放
- 后台播放 + 系统媒体通知 / 锁屏控制、画中画（手动或按 Home 自动进入）
- 断点续播、同步网站观看历史

**账号与社交**
- 邮箱或用户名登录，收藏（点赞）、关注作者、关注动态
- 评论：查看、发表、楼中楼回复、编辑 / 删除
- 播放列表管理、通知中心、私信会话、好友与好友请求

**其他**
- 离线下载：后台下载、暂停 / 继续、通知栏进度、链接过期自动重新获取、本地播放
- 内置 HTTP 代理（API、图片、视频、下载均生效）
- 打开 iwara.tv 链接直接跳转到 App 对应页面
- Material 3，跟随系统深浅色，可选主题色

<!-- 截图：建议放在 docs/screenshots/ 并在此引用，注意避免成人内容 -->

## 📥 下载安装

前往 [Releases](https://github.com/Sakura-Natsu/Iwara-Flutter/releases) 下载：

| 文件 | 适用设备 |
| --- | --- |
| `Iwara-x.y.z-arm64-v8a.apk` | 绝大多数手机（2017 年以后的机型） |
| `Iwara-x.y.z-armeabi-v7a.apk` | 较老的 32 位设备 |
| `Iwara-x.y.z-x86_64.apk` | 模拟器 / x86 设备 |

## 📖 使用说明

- **网络**：如果代理软件使用 VPN 模式，无需额外设置；如果只开启了 HTTP 代理，在「设置 → 网络」中填写代理地址（如 `127.0.0.1:7890`），并用「测试连接」检查。
- **登录**：使用 iwara.tv 的邮箱或用户名登录。App 只保存登录令牌（Android Keystore 加密存储），不保存密码。
- **画面黑屏 / 花屏**：在「设置 → 视频输出」切换为「MediaCodec 直出」或「软件解码」。
- **下载一直「等待网络」**：后台下载依赖系统判定网络可用。原生 Android 在无法访问 Google 连通性检测且未开启 VPN 时会判定网络不可用，把代理软件切换为 VPN 模式即可（国产 ROM 一般不受影响）。
- **播放源获取失败**：视频直链需要签名，签名参数写在官网前端中。官网更新后 App 会自动重新提取，也可在「设置 → 视频签名」手动更新。

## 🔨 构建

环境要求：Flutter 3.44+（Dart 3.12+）、JDK 17+、Android SDK。

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

产物位于 `build/app/outputs/flutter-apk/`。

> [!NOTE]
> `media_kit_libs_android_video` 会在 Gradle 构建时从 GitHub 下载 libmpv。网络受限导致超时时，可通过代理手动下载
> [v1.1.7](https://github.com/media-kit/libmpv-android-video-build/releases/tag/v1.1.7) 的
> `default-{arm64-v8a,armeabi-v7a,x86_64,x86}.jar` 到 `build/media_kit_libs_android_video/v1.1.7/`，构建脚本校验 MD5 后会跳过下载。

### 签名

未配置时 Release 包使用 debug 签名。正式发布请创建自己的密钥：

```bash
keytool -genkey -v -keystore android/app/release.jks -keyalg RSA -keysize 2048 -validity 36500 -alias iwara
```

然后创建 `android/key.properties`（已被 `.gitignore` 忽略，切勿提交）：

```properties
storeFile=release.jks
storePassword=你的密码
keyAlias=iwara
keyPassword=你的密码
```

### 自动发布

推送 `v*` 标签（如 `v1.0.1`）后，GitHub Actions 会自动构建 APK 并发布到 Releases。在仓库 **Settings → Secrets and variables → Actions** 中配置以下 Secrets 以使用正式签名：

| Secret | 内容 |
| --- | --- |
| `KEYSTORE_BASE64` | keystore 文件的 base64（`base64 -w0 android/app/release.jks`） |
| `KEYSTORE_PASSWORD` | keystore 密码 |
| `KEY_ALIAS` | 密钥别名 |
| `KEY_PASSWORD` | 密钥密码 |

未配置时会以临时 debug 签名构建。这样每次构建的签名都不同，用户无法覆盖升级，只适合测试。

发布新版本的流程：
1. 修改 `pubspec.yaml` 中的 `version`（如 `1.2.0+5`，`+` 后的构建号需递增）。
2. 在 `CHANGELOG.md` 顶部添加 `## v1.2.0` 小节。这段内容会作为 Release 说明，也会显示在 App 的更新提示里。
3. 提交后打标签并推送：`git tag v1.2.0 && git push origin v1.2.0`。

## 🗂️ 项目结构

```
lib/
├── api/          # 网络层：鉴权与 token 刷新、全部接口、图片地址构造、错误翻译
├── core/         # 常量、设置、全局代理、格式化
├── models/       # 数据模型
├── player/       # 播放器控制器、手势控制层、全屏、画中画、媒体通知
├── services/     # 本地数据库（播放进度、搜索历史）、下载管理
├── widgets/      # 通用组件：分页列表、卡片、图片、富文本、状态视图
├── pages/        # 各功能页面
├── router.dart   # 路由（兼容官网链接格式）
└── main.dart
android/app/src/main/kotlin/…/MainActivity.kt  # 画中画原生实现
docs/
├── API.md          # Iwara 接口笔记（逆向自官网前端）
└── CONVENTIONS.md  # 开发约定
```

## 🧰 技术栈

[Riverpod](https://riverpod.dev) · [go_router](https://pub.dev/packages/go_router) · [Dio](https://pub.dev/packages/dio) · [media_kit](https://github.com/media-kit/media-kit) · [audio_service](https://pub.dev/packages/audio_service) · [background_downloader](https://pub.dev/packages/background_downloader) · [cached_network_image](https://pub.dev/packages/cached_network_image) · [sqflite](https://pub.dev/packages/sqflite)

## 🤝 参与贡献

欢迎提交 Issue 和 PR。开始前请阅读 [开发约定](docs/CONVENTIONS.md) 和 [接口笔记](docs/API.md)，提交前确保 `flutter analyze` 无问题。

<details>
<summary>模拟器调试小贴士</summary>

- 模拟器需要代理时，可以用 `emulator -avd <名称> -http-proxy http://127.0.0.1:7890` 启动。这样会透明代理全部流量，系统网络也能通过验证；也可以在 App 设置中把代理设为 `10.0.2.2:7890`。
- 部分模拟器（gfxstream GPU）上 libmpv 的画面显示为黑屏，但声音和进度正常。这是模拟器兼容性问题，请以真机为准。
- 项目和 Pub 缓存不在同一个盘符时，Kotlin 增量编译会失败，所以 `android/gradle.properties` 中已关闭增量编译。

</details>

## 🙏 致谢

- [Iwara](https://www.iwara.tv) 以及所有创作者
- [media_kit](https://github.com/media-kit/media-kit) 提供强大的跨平台播放能力
- 应用图标中的初音未来形象 © Crypton Future Media, INC. [www.piapro.net](https://piapro.net)，遵循 [Piapro Character License](https://piapro.net/intl/en_for_creators.html) 非商业使用

## 📄 许可证

[GPL-3.0](LICENSE)
