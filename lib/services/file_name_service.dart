import 'dart:io';

import 'package:path/path.dart' as p;

class FileNameService {
  static String sanitize(String input) {
    var name = p.basename(input).replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    name = name.trim();
    if (name.isEmpty || name == '.' || name == '..') {
      return 'file';
    }
    return name;
  }

  static Future<File> uniqueFile(Directory directory, String originalName) async {
    final safeName = sanitize(originalName);
    final extension = p.extension(safeName);
    final basename = p.basenameWithoutExtension(safeName);

    var candidate = File(p.join(directory.path, safeName));
    var index = 1;
    while (await candidate.exists() || await File('${candidate.path}.part').exists()) {
      final nextName = '$basename ($index)$extension';
      candidate = File(p.join(directory.path, nextName));
      index += 1;
    }

    return candidate;
  }
}
