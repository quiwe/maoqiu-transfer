import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _saveDirectoryKey = 'save_directory';

  SharedPreferences? _prefs;
  String? _saveDirectory;

  String? get saveDirectory => _saveDirectory;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _saveDirectory = _prefs?.getString(_saveDirectoryKey);
    if (_saveDirectory == null || _saveDirectory!.isEmpty) {
      final fallback = await defaultSaveDirectory();
      _saveDirectory = fallback.path;
      await _prefs?.setString(_saveDirectoryKey, fallback.path);
    }
  }

  Future<Directory> getSaveDirectory() async {
    final path = _saveDirectory;
    if (path != null && path.isNotEmpty) {
      final directory = await _tryCreateDirectory(Directory(path));
      if (directory != null) {
        return directory;
      }
    }

    final fallback = await defaultSaveDirectory();
    _saveDirectory = fallback.path;
    await _prefs?.setString(_saveDirectoryKey, fallback.path);
    return fallback;
  }

  Future<void> setSaveDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _saveDirectory = directory.path;
    await _prefs?.setString(_saveDirectoryKey, directory.path);
  }

  Future<Directory> defaultSaveDirectory() async {
    final candidates = <Directory?>[];
    try {
      if (Platform.isAndroid) {
        final externalDownloads = await getExternalStorageDirectories(
          type: StorageDirectory.downloads,
        );
        if (externalDownloads != null && externalDownloads.isNotEmpty) {
          candidates.add(externalDownloads.first);
        }
      } else {
        candidates.add(await getDownloadsDirectory());
      }
    } catch (_) {
      // Some sandboxed desktop builds cannot resolve the downloads directory.
    }

    try {
      candidates.add(await getApplicationDocumentsDirectory());
    } catch (_) {
      // Fall through to the temporary directory fallback below.
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
        Directory(p.join(base.path, 'MaoQiuTransfer')),
      );
      if (directory != null) {
        return directory;
      }
    }

    throw FileSystemException('No writable save directory is available.');
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
}
