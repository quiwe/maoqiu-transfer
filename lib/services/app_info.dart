import 'dart:io';

class AppInfo {
  static const String appName = '毛球互传';
  static const String version = '0.2.2';
  static const int buildNumber = 4;
  static const String repository = 'quiwe/maoqiu-transfer';
  static const String latestReleaseApiUrl =
      'https://api.github.com/repos/quiwe/maoqiu-transfer/releases/latest';
  static const String releasesUrl =
      'https://github.com/quiwe/maoqiu-transfer/releases';

  static String get platformKey {
    if (Platform.isAndroid) {
      return 'android';
    }
    if (Platform.isWindows) {
      return 'windows';
    }
    if (Platform.isMacOS) {
      return 'macos';
    }
    if (Platform.isLinux) {
      return 'linux';
    }
    return 'unknown';
  }

  static String get platformLabel {
    switch (platformKey) {
      case 'android':
        return 'Android';
      case 'windows':
        return 'Windows';
      case 'macos':
        return 'macOS';
      case 'linux':
        return 'Linux';
      default:
        return '当前平台';
    }
  }
}
