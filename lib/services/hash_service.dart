import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

class HashService {
  Future<String> sha256ForFile(
    String path, {
    void Function(int bytesRead)? onProgress,
  }) async {
    final digestSink = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(digestSink);
    var read = 0;

    await for (final chunk in File(path).openRead()) {
      input.add(chunk);
      read += chunk.length;
      onProgress?.call(read);
    }

    input.close();
    return digestSink.events.single.toString();
  }
}
