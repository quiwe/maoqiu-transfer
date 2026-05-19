import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../models/device_info.dart';
import '../models/transfer_file.dart';
import '../models/transfer_task.dart';
import 'hash_service.dart';
import 'history_service.dart';
import 'protocol.dart';

class FileSenderService {
  FileSenderService({
    required HashService hashService,
    required HistoryService historyService,
  })  : _hashService = hashService,
        _historyService = historyService;

  final HashService _hashService;
  final HistoryService _historyService;
  final StreamController<TransferTask> _taskController =
      StreamController<TransferTask>.broadcast();
  final Uuid _uuid = const Uuid();

  Stream<TransferTask> get taskEvents => _taskController.stream;

  String sendFiles({
    required DeviceInfo localDevice,
    required DeviceInfo peer,
    required List<TransferFile> files,
    List<String> peerIpCandidates = const [],
  }) {
    if (files.isEmpty) {
      throw ArgumentError('No files selected.');
    }
    final taskId = _uuid.v4();
    unawaited(_sendFiles(taskId, localDevice, peer, files, peerIpCandidates));
    return taskId;
  }

  Future<void> dispose() => _taskController.close();

  Future<void> _sendFiles(
    String taskId,
    DeviceInfo localDevice,
    DeviceInfo peer,
    List<TransferFile> files,
    List<String> peerIpCandidates,
  ) async {
    final createdAt = DateTime.now();
    var task = TransferTask(
      taskId: taskId,
      direction: TransferDirection.send,
      peerDeviceName: peer.deviceName,
      files: files,
      status: TransferStatus.pending,
      totalBytes: files.fold(0, (sum, file) => sum + file.fileSize),
      transferredBytes: 0,
      currentFileName: files.isEmpty ? null : files.first.fileName,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    var historyWritten = false;
    _emitTask(task);

    try {
      final filesWithHashes = <TransferFile>[];
      for (final file in files) {
        final path = file.localPath;
        if (path == null || path.isEmpty) {
          throw FileSystemException('Selected file has no local path', file.fileName);
        }

        task = task.copyWith(
          status: TransferStatus.pending,
          currentFileName: '校验 ${file.fileName}',
        );
        _emitTask(task);

        final digest = file.sha256.isEmpty
            ? await _hashService.sha256ForFile(path)
            : file.sha256;
        filesWithHashes.add(file.copyWith(sha256: digest));
      }

      task = task.copyWith(
        files: filesWithHashes,
        status: TransferStatus.waitingAccept,
        currentFileName: filesWithHashes.first.fileName,
      );
      _emitTask(task);

      final socket = await _connectToPeer(peer, peerIpCandidates);
      final reader = SocketReader(socket);
      try {
        socket.setOption(SocketOption.tcpNoDelay, true);
        await TransferProtocol.writeJson(socket, {
          'type': 'transfer_request',
          'taskId': taskId,
          'senderDeviceId': localDevice.deviceId,
          'senderDeviceName': localDevice.deviceName,
          'files': filesWithHashes.map((file) => file.toJson()).toList(),
        });

        final response = await TransferProtocol.readJson(reader).timeout(
          const Duration(minutes: 2),
        );
        if (response['type'] == 'transfer_reject') {
          task = task.copyWith(status: TransferStatus.rejected);
          await _recordHistory(task, TransferStatus.rejected);
          historyWritten = true;
          _emitTask(task);
          return;
        }
        if (response['type'] != 'transfer_accept') {
          throw const FormatException('Expected transfer_accept.');
        }

        task = task.copyWith(
          status: TransferStatus.transferring,
          transferredBytes: 0,
          currentFileName: filesWithHashes.first.fileName,
          clearError: true,
        );
        _emitTask(task);

        var transferred = 0;
        var lastEmit = DateTime.now();
        for (final file in filesWithHashes) {
          await TransferProtocol.writeJson(socket, {
            'type': 'file_start',
            'taskId': taskId,
            ...file.toJson(),
          });

          final path = file.localPath!;
          await for (final chunk in File(path).openRead()) {
            socket.add(chunk);
            transferred += chunk.length;

            final now = DateTime.now();
            if (now.difference(lastEmit).inMilliseconds >= 120 ||
                transferred == task.totalBytes) {
              task = task.copyWith(
                status: TransferStatus.transferring,
                transferredBytes: transferred,
                currentFileName: file.fileName,
              );
              _emitTask(task);
              lastEmit = now;
            }
          }
          await socket.flush();

          final ack = await TransferProtocol.readJson(reader);
          if (ack['type'] != 'file_received' || ack['status'] != 'success') {
            throw FileSystemException('Receiver failed to save file');
          }
        }

        await TransferProtocol.writeJson(socket, {
          'type': 'transfer_complete',
          'taskId': taskId,
          'status': 'success',
        });

        task = task.copyWith(
          status: TransferStatus.completed,
          transferredBytes: task.totalBytes,
          currentFileName: filesWithHashes.last.fileName,
          files: filesWithHashes,
        );
        await _recordHistory(task, TransferStatus.completed);
        historyWritten = true;
        _emitTask(task);
      } finally {
        await reader.cancel();
        await socket.close();
      }
    } catch (error) {
      task = task.copyWith(
        status: TransferStatus.failed,
        errorMessage: error.toString(),
      );
      if (!historyWritten) {
        await _recordHistory(task, TransferStatus.failed);
      }
      _emitTask(task);
    }
  }

  Future<void> _recordHistory(TransferTask task, TransferStatus status) async {
    await _historyService.addRecords(
      task.files.map(
        (file) => TransferHistoryRecord(
          taskId: task.taskId,
          direction: TransferDirection.send,
          peerDeviceName: task.peerDeviceName,
          fileName: file.fileName,
          fileSize: file.fileSize,
          status: status,
          savePath: file.localPath,
          createdAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<Socket> _connectToPeer(
    DeviceInfo peer,
    List<String> peerIpCandidates,
  ) async {
    final candidates = <String>{
      if (peer.ip.trim().isNotEmpty) peer.ip.trim(),
      ...peerIpCandidates.where((ip) => ip.trim().isNotEmpty).map((ip) => ip.trim()),
    }.toList();

    Object? lastError;
    for (final ip in candidates) {
      try {
        return await Socket.connect(
          ip,
          peer.port,
          timeout: const Duration(seconds: 8),
        );
      } catch (error) {
        lastError = error;
      }
    }

    throw StateError('无法连接 ${peer.deviceName}：$lastError');
  }

  void _emitTask(TransferTask task) {
    if (!_taskController.isClosed) {
      _taskController.add(task);
    }
  }
}
