import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';

/// 在 main() 中初始化后通过 override 注入。
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider 未初始化'),
);

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.seedColor = 0xFF00BCD4,
    this.proxyEnabled = false,
    this.proxyHost = '127.0.0.1',
    this.proxyPort = 7890,
    this.rating = Rating.all,
    this.defaultQuality = 'Source',
    this.autoPlay = true,
    this.backgroundPlay = true,
    this.autoPip = true,
    this.resumePlayback = true,
    this.longPressSpeed = 2.0,
    this.videoOutput = 'gpu',
    this.autoCheckUpdate = true,
    this.ignoredVersion,
    this.videoSalt,
  });

  final ThemeMode themeMode;
  final int seedColor;
  final bool proxyEnabled;
  final String proxyHost;
  final int proxyPort;
  final Rating rating;

  /// Source / 540 / 360
  final String defaultQuality;
  final bool autoPlay;
  final bool backgroundPlay;
  final bool autoPip;
  final bool resumePlayback;
  final double longPressSpeed;

  /// 视频输出模式：gpu（GPU 渲染 + 硬解）/ gpu-sw（软解）/ mediacodec（MediaCodec 直出）。
  final String videoOutput;

  /// 启动时自动检查 GitHub 上的新版本。
  final bool autoCheckUpdate;

  /// 用户选择「忽略此版本」的版本号（如 1.2.0）。
  final String? ignoredVersion;

  /// 从前端 JS 自动提取到的签名盐值；为空时使用内置默认值。
  final String? videoSalt;

  String? get proxyAddress =>
      proxyEnabled && proxyHost.isNotEmpty ? '$proxyHost:$proxyPort' : null;

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? seedColor,
    bool? proxyEnabled,
    String? proxyHost,
    int? proxyPort,
    Rating? rating,
    String? defaultQuality,
    bool? autoPlay,
    bool? backgroundPlay,
    bool? autoPip,
    bool? resumePlayback,
    double? longPressSpeed,
    String? videoOutput,
    bool? autoCheckUpdate,
    String? ignoredVersion,
    String? videoSalt,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      seedColor: seedColor ?? this.seedColor,
      proxyEnabled: proxyEnabled ?? this.proxyEnabled,
      proxyHost: proxyHost ?? this.proxyHost,
      proxyPort: proxyPort ?? this.proxyPort,
      rating: rating ?? this.rating,
      defaultQuality: defaultQuality ?? this.defaultQuality,
      autoPlay: autoPlay ?? this.autoPlay,
      backgroundPlay: backgroundPlay ?? this.backgroundPlay,
      autoPip: autoPip ?? this.autoPip,
      resumePlayback: resumePlayback ?? this.resumePlayback,
      longPressSpeed: longPressSpeed ?? this.longPressSpeed,
      videoOutput: videoOutput ?? this.videoOutput,
      autoCheckUpdate: autoCheckUpdate ?? this.autoCheckUpdate,
      ignoredVersion: ignoredVersion ?? this.ignoredVersion,
      videoSalt: videoSalt ?? this.videoSalt,
    );
  }

  static AppSettings load(SharedPreferences p) {
    const d = AppSettings();
    return AppSettings(
      themeMode:
          ThemeMode.values[(p.getInt('themeMode') ?? d.themeMode.index).clamp(
            0,
            ThemeMode.values.length - 1,
          )],
      seedColor: p.getInt('seedColor') ?? d.seedColor,
      proxyEnabled: p.getBool('proxyEnabled') ?? d.proxyEnabled,
      proxyHost: p.getString('proxyHost') ?? d.proxyHost,
      proxyPort: p.getInt('proxyPort') ?? d.proxyPort,
      rating: Rating.parse(p.getString('rating')),
      defaultQuality: p.getString('defaultQuality') ?? d.defaultQuality,
      autoPlay: p.getBool('autoPlay') ?? d.autoPlay,
      backgroundPlay: p.getBool('backgroundPlay') ?? d.backgroundPlay,
      autoPip: p.getBool('autoPip') ?? d.autoPip,
      resumePlayback: p.getBool('resumePlayback') ?? d.resumePlayback,
      longPressSpeed: p.getDouble('longPressSpeed') ?? d.longPressSpeed,
      videoOutput: p.getString('videoOutput') ?? d.videoOutput,
      autoCheckUpdate: p.getBool('autoCheckUpdate') ?? d.autoCheckUpdate,
      ignoredVersion: p.getString('ignoredVersion'),
      videoSalt: p.getString('videoSalt'),
    );
  }

  Future<void> save(SharedPreferences p) async {
    await p.setInt('themeMode', themeMode.index);
    await p.setInt('seedColor', seedColor);
    await p.setBool('proxyEnabled', proxyEnabled);
    await p.setString('proxyHost', proxyHost);
    await p.setInt('proxyPort', proxyPort);
    await p.setString('rating', rating.value);
    await p.setString('defaultQuality', defaultQuality);
    await p.setBool('autoPlay', autoPlay);
    await p.setBool('backgroundPlay', backgroundPlay);
    await p.setBool('autoPip', autoPip);
    await p.setBool('resumePlayback', resumePlayback);
    await p.setDouble('longPressSpeed', longPressSpeed);
    await p.setString('videoOutput', videoOutput);
    await p.setBool('autoCheckUpdate', autoCheckUpdate);
    if (ignoredVersion != null) {
      await p.setString('ignoredVersion', ignoredVersion!);
    }
    if (videoSalt != null) await p.setString('videoSalt', videoSalt!);
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.load(ref.watch(sharedPrefsProvider));

  Future<void> update(AppSettings Function(AppSettings s) fn) async {
    state = fn(state);
    await state.save(ref.read(sharedPrefsProvider));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
