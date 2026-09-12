import 'dart:io';

import 'package:flutter/services.dart';

/// Нативная проверка APK перед установкой и запасной способ открыть
/// системный установщик, чтобы получить более детальные логи.
class InstallService {
  static const _channel = MethodChannel('bizzy/install');

  static Future<ApkInfo?> getApkInfo(String path) async {
    if (!Platform.isAndroid) return null;
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('getApkInfo', {
        'path': path,
      });
      if (map == null) return null;
      return ApkInfo(
        packageName: (map['packageName'] as String?) ?? '',
        versionName: (map['versionName'] as String?) ?? '',
        versionCode: (map['versionCode'] as int?) ?? 0,
        signatureSha256: (map['signatureSha256'] as String?) ?? '',
      );
    } catch (e) {
      return null;
    }
  }

  static Future<String?> getInstalledSignature(String packageName) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>(
        'getInstalledSignature',
        {'packageName': packageName},
      );
    } catch (e) {
      return null;
    }
  }

  static Future<String?> getDeviceInfo() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getDeviceInfo');
    } catch (e) {
      return null;
    }
  }

  /// Открывает APK через системный установщик без ожидания результата.
  /// Используется как fallback, если install_plugin_v3 вернул неинформативную
  /// ошибку "Install Cancel".
  static Future<void> openApk(String path) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openApk', {'path': path});
    } catch (_) {}
  }
}

class ApkInfo {
  const ApkInfo({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.signatureSha256,
  });

  final String packageName;
  final String versionName;
  final int versionCode;
  final String signatureSha256;

  @override
  String toString() =>
      'package=$packageName version=$versionName($versionCode) sig=$signatureSha256';
}
