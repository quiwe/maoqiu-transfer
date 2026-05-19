import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'app_info.dart';

class TransferProtocol {
  static const int udpPort = 9526;
  static const int tcpPort = 9527;
  static const String appVersion = AppInfo.version;
  static const Duration broadcastInterval = Duration(seconds: 2);
  static const Duration offlineAfter = Duration(seconds: 8);
  static const int chunkSize = 1024 * 1024;
  static const int maxJsonFrameBytes = 1024 * 1024;

  static Future<void> writeJson(
    Socket socket,
    Map<String, dynamic> message,
  ) async {
    final payload = utf8.encode(jsonEncode(message));
    final header = ByteData(4)..setUint32(0, payload.length, Endian.big);
    socket.add(header.buffer.asUint8List());
    socket.add(payload);
    await socket.flush();
  }

  static Future<Map<String, dynamic>> readJson(SocketReader reader) async {
    final header = await reader.readExact(4);
    final length = ByteData.sublistView(header).getUint32(0, Endian.big);
    if (length <= 0 || length > maxJsonFrameBytes) {
      throw const FormatException('Invalid JSON frame length.');
    }
    final body = await reader.readExact(length);
    final decoded = jsonDecode(utf8.decode(body));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON frame must be an object.');
    }
    return decoded;
  }
}

class SocketReader {
  SocketReader(Stream<List<int>> stream) : _iterator = StreamIterator(stream);

  final StreamIterator<List<int>> _iterator;
  final Queue<Uint8List> _chunks = Queue<Uint8List>();
  int _chunkOffset = 0;
  int _available = 0;

  Future<Uint8List> readExact(int length) async {
    if (length < 0) {
      throw ArgumentError.value(length, 'length');
    }
    while (_available < length) {
      await _fill();
    }
    return _drain(length);
  }

  Future<Uint8List> readUpTo(int maxLength) async {
    if (maxLength <= 0) {
      return Uint8List(0);
    }
    while (_available == 0) {
      await _fill();
    }
    return _drain(min(maxLength, _available));
  }

  Future<void> cancel() => _iterator.cancel();

  Future<void> _fill() async {
    final hasNext = await _iterator.moveNext();
    if (!hasNext) {
      throw const SocketException('Socket closed before expected bytes arrived.');
    }
    final current = Uint8List.fromList(_iterator.current);
    if (current.isEmpty) {
      return;
    }
    _chunks.add(current);
    _available += current.length;
  }

  Uint8List _drain(int length) {
    final output = Uint8List(length);
    var written = 0;

    while (written < length) {
      final chunk = _chunks.first;
      final readable = chunk.length - _chunkOffset;
      final take = min(readable, length - written);
      output.setRange(written, written + take, chunk, _chunkOffset);

      written += take;
      _chunkOffset += take;
      _available -= take;

      if (_chunkOffset >= chunk.length) {
        _chunks.removeFirst();
        _chunkOffset = 0;
      }
    }

    return output;
  }
}
