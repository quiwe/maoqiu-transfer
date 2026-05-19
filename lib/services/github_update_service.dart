import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_update.dart';
import 'app_info.dart';
import 'file_name_service.dart';

class GitHubUpdateService {
  GitHubUpdateService({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<AppUpdateInfo?> checkForUpdate() async {
    final release = await _fetchLatestRelease();
    final tagName = release['tag_name'] as String? ?? '';
    final latestVersion = _normalizeVersion(tagName);

    if (latestVersion.isEmpty ||
        _compareVersions(latestVersion, AppInfo.version) <= 0) {
      return null;
    }

    final assets = (release['assets'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final asset = _selectPlatformAsset(assets);
    if (asset == null) {
      throw StateError(
        '发现新版本 $latestVersion，但没有 ${AppInfo.platformLabel} 安装包。',
      );
    }

    return AppUpdateInfo(
      version: latestVersion,
      tagName: tagName,
      releaseName: release['name'] as String? ?? tagName,
      releaseUrl: release['html_url'] as String? ?? AppInfo.releasesUrl,
      assetName: asset['name'] as String? ?? 'maoqiu-transfer-$latestVersion',
      downloadUrl: asset['browser_download_url'] as String? ?? '',
      size: (asset['size'] as num?)?.toInt() ?? 0,
      publishedAt: DateTime.tryParse(release['published_at'] as String? ?? ''),
      body: release['body'] as String? ?? '',
    );
  }

  Stream<UpdateDownloadState> downloadUpdate(AppUpdateInfo update) async* {
    IOSink? output;
    File? partFile;

    try {
      final directory = await _updatesDirectory();
      final target = await FileNameService.uniqueFile(directory, update.assetName);
      partFile = File('${target.path}.part');
      if (await partFile.exists()) {
        await partFile.delete();
      }

      final request = await _client.getUrl(Uri.parse(update.downloadUrl));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/octet-stream')
        ..set(HttpHeaders.userAgentHeader, 'MaoQiuTransfer/${AppInfo.version}');
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          '下载失败：HTTP ${response.statusCode}',
          uri: Uri.parse(update.downloadUrl),
        );
      }

      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : update.size;
      var receivedBytes = 0;
      var lastEmit = DateTime.now();
      output = partFile.openWrite();

      yield UpdateDownloadState(
        status: UpdateDownloadStatus.downloading,
        totalBytes: totalBytes,
      );

      await for (final chunk in response) {
        output.add(chunk);
        receivedBytes += chunk.length;

        final now = DateTime.now();
        if (now.difference(lastEmit).inMilliseconds >= 120 ||
            receivedBytes == totalBytes) {
          yield UpdateDownloadState(
            status: UpdateDownloadStatus.downloading,
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          );
          lastEmit = now;
        }
      }

      await output.flush();
      await output.close();
      output = null;

      final saved = await partFile.rename(target.path);
      yield UpdateDownloadState(
        status: UpdateDownloadStatus.downloaded,
        receivedBytes: receivedBytes,
        totalBytes: totalBytes,
        filePath: saved.path,
      );
    } catch (error) {
      await output?.close();
      if (partFile != null && await partFile.exists()) {
        await partFile.delete();
      }
      yield UpdateDownloadState(
        status: UpdateDownloadStatus.failed,
        errorMessage: error.toString(),
      );
    }
  }

  void dispose() {
    _client.close(force: true);
  }

  Future<Map<String, dynamic>> _fetchLatestRelease() async {
    final uri = Uri.parse(AppInfo.latestReleaseApiUrl);
    final request = await _client.getUrl(uri);
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, 'MaoQiuTransfer/${AppInfo.version}');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        '检查更新失败：HTTP ${response.statusCode}',
        uri: uri,
      );
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('GitHub Release 响应格式不正确。');
    }
    return decoded;
  }

  Map<String, dynamic>? _selectPlatformAsset(List<Map<String, dynamic>> assets) {
    int matchScore(String name) {
      final lower = name.toLowerCase();
      switch (AppInfo.platformKey) {
        case 'android':
          return lower.endsWith('.apk') ? 1 : 0;
        case 'windows':
          return lower.endsWith('.exe') &&
                  (lower.contains('windows') || lower.contains('win'))
              ? 1
              : 0;
        case 'macos':
          final isMac = lower.contains('macos') ||
              lower.contains('darwin') ||
              lower.contains('mac');
          if (!isMac) {
            return 0;
          }
          if (lower.endsWith('.pkg')) {
            return 2;
          }
          return lower.endsWith('.dmg') ? 1 : 0;
        case 'linux':
          return lower.contains('linux') &&
                  (lower.endsWith('.appimage') ||
                      lower.endsWith('.deb') ||
                      lower.endsWith('.tar.gz') ||
                      lower.endsWith('.zip'))
              ? 1
              : 0;
        default:
          return 0;
      }
    }

    Map<String, dynamic>? bestAsset;
    var bestScore = 0;
    for (final asset in assets) {
      final name = asset['name'] as String? ?? '';
      final score = matchScore(name);
      if (score > bestScore) {
        bestScore = score;
        bestAsset = asset;
      }
    }
    return bestAsset;
  }

  Future<Directory> _updatesDirectory() async {
    final candidates = <Directory?>[];
    try {
      if (Platform.isAndroid) {
        final directories = await getExternalStorageDirectories(
          type: StorageDirectory.downloads,
        );
        if (directories != null && directories.isNotEmpty) {
          candidates.add(directories.first);
        }
      } else {
        candidates.add(await getDownloadsDirectory());
      }
    } catch (_) {
      // Desktop sandboxing can deny access to Downloads.
    }

    try {
      candidates.add(await getApplicationDocumentsDirectory());
    } catch (_) {
      // Fall through to the temporary directory fallback.
    }
    try {
      candidates.add(await getTemporaryDirectory());
    } catch (_) {
      // The final error below is clearer than surfacing a platform exception.
    }

    for (final base in candidates) {
      if (base == null) {
        continue;
      }
      final directory = await _tryCreateDirectory(
        Directory(p.join(base.path, 'MaoQiuTransfer', 'Updates')),
      );
      if (directory != null) {
        return directory;
      }
    }

    throw FileSystemException('No writable update directory is available.');
  }

  Future<Directory?> _tryCreateDirectory(Directory directory) async {
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    } on FileSystemException {
      return null;
    }
  }

  String _normalizeVersion(String raw) {
    return raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
  }

  int _compareVersions(String left, String right) {
    List<int> parse(String value) {
      final core = value.split(RegExp(r'[-+]')).first;
      return core
          .split('.')
          .map((part) => int.tryParse(part) ?? 0)
          .toList(growable: false);
    }

    final a = parse(left);
    final b = parse(right);
    final length = a.length > b.length ? a.length : b.length;
    for (var index = 0; index < length; index += 1) {
      final leftPart = index < a.length ? a[index] : 0;
      final rightPart = index < b.length ? b[index] : 0;
      if (leftPart != rightPart) {
        return leftPart.compareTo(rightPart);
      }
    }
    return 0;
  }
}
