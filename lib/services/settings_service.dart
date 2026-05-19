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
    _saveDirectory ??= (await defaultSaveDirectory()).path;
  }

  Future<Directory> getSaveDirectory() async {
    final path = _saveDirectory;
    if (path == null || path.isEmpty) {
      final fallback = await defaultSaveDirectory();
      _saveDirectory = fallback.path;
      return fallback;
    }
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
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
    Directory? base;
    try {
      if (Platform.isAndroid) {
        final externalDownloads = await getExternalStorageDirectories(
          type: StorageDirectory.downloads,
        );
        if (externalDownloads != null && externalDownloads.isNotEmpty) {
          base = externalDownloads.first;
        }
      } else {
        base = await getDownloadsDirectory();
      }
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();

    final directory = Directory(p.join(base.path, 'MaoQiuTransfer'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}
