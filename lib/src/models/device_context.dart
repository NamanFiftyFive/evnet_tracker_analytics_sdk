import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Device details sent once per batch (the server's `context`). Collected at init.
class DeviceContext {
  const DeviceContext({
    this.platform = 'flutter',
    this.os,
    this.browser,
    this.deviceType,
    this.appVersion,
  });

  final String platform;
  final String? os;
  final String? browser;

  /// One of: mobile, tablet, desktop, tv, other.
  final String? deviceType;
  final String? appVersion;

  Map<String, Object?> toJson() => {
        'platform': platform,
        if (os != null) 'os': os,
        if (browser != null) 'browser': browser,
        if (deviceType != null) 'device_type': deviceType,
        if (appVersion != null) 'app_version': appVersion,
      };

  /// Reads the device and app details. Never throws: anything unavailable is left out.
  static Future<DeviceContext> collect() async {
    final appVersion = await _appVersion();
    try {
      final info = DeviceInfoPlugin();
      if (kIsWeb) {
        final web = await info.webBrowserInfo;
        final mobile = (web.userAgent ?? '').contains('Mobi');
        return DeviceContext(
          os: web.platform,
          browser: web.browserName.name,
          deviceType: mobile ? 'mobile' : 'desktop',
          appVersion: appVersion,
        );
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final android = await info.androidInfo;
          return DeviceContext(
            os: 'Android ${android.version.release}',
            deviceType: 'mobile',
            appVersion: appVersion,
          );
        case TargetPlatform.iOS:
          final ios = await info.iosInfo;
          return DeviceContext(
            os: 'iOS ${ios.systemVersion}',
            deviceType: ios.model.toLowerCase().contains('ipad') ? 'tablet' : 'mobile',
            appVersion: appVersion,
          );
        case TargetPlatform.macOS:
        case TargetPlatform.windows:
        case TargetPlatform.linux:
          return DeviceContext(
            os: defaultTargetPlatform.name,
            deviceType: 'desktop',
            appVersion: appVersion,
          );
        case TargetPlatform.fuchsia:
          return DeviceContext(os: 'fuchsia', deviceType: 'other', appVersion: appVersion);
      }
    } catch (_) {
      // Plugin not available (e.g. in tests): send what we know.
      return DeviceContext(os: defaultTargetPlatform.name, appVersion: appVersion);
    }
  }

  static Future<String?> _appVersion() async {
    try {
      final package = await PackageInfo.fromPlatform();
      if (package.version.isEmpty) return null;
      return package.buildNumber.isEmpty ? package.version : '${package.version}+${package.buildNumber}';
    } catch (_) {
      return null;
    }
  }
}
