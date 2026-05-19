import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

import '../models/device_info.dart';
import '../models/transfer_file.dart';
import '../models/transfer_task.dart';
import 'file_name_service.dart';
import 'history_service.dart';
import 'protocol.dart';
import 'settings_service.dart';

class IncomingTransferRequest {
  IncomingTransferRequest({
    required this.taskId,
    required this.senderDeviceId,
    required this.senderDeviceName,
    required this.files,
  });

  final String taskId;
  final String senderDeviceId;
  final String senderDeviceName;
  final List<TransferFile> files;
  final Completer<bool> _decision = Completer<bool>();

  int get totalBytes => files.fold(0, (sum, file) => sum + file.fileSize);

  Future<bool> get decision => _decision.future;

  void accept() {
    if (!_decision.isCompleted) {
      _decision.complete(true);
    }
  }

  void reject() {
    if (!_decision.isCompleted) {
      _decision.complete(false);
    }
  }
}

class HotspotJoinRequest {
  HotspotJoinRequest({
    required this.token,
    required this.receiverDeviceId,
    required this.receiverDeviceName,
    required this.receiverDeviceType,
    required this.receiverIp,
    required this.receiverPort,
    required this.version,
  });

  final String token;
  final String receiverDeviceId;
  final String receiverDeviceName;
  final String receiverDeviceType;
  final String receiverIp;
  final int receiverPort;
  final String version;
  final Completer<bool> _decision = Completer<bool>();

  Future<bool> get decision => _decision.future;

  DeviceInfo toDeviceInfo() {
    return DeviceInfo(
      deviceId: receiverDeviceId,
      deviceName: receiverDeviceName,
      deviceType: receiverDeviceType,
      ip: receiverIp,
      port: receiverPort,
      version: version,
      lastSeen: DateTime.now(),
    );
  }

  void accept() {
    if (!_decision.isCompleted) {
      _decision.complete(true);
    }
  }

  void reject() {
    if (!_decision.isCompleted) {
      _decision.complete(false);
    }
  }
}

class ReceiverHotspotReadyRequest {
  ReceiverHotspotReadyRequest({
    required this.token,
    required this.receiverDeviceId,
    required this.receiverDeviceName,
    required this.receiverDeviceType,
    required this.receiverPort,
    required this.version,
    required this.ssid,
    required this.password,
    required this.hostIp,
    required this.hostIpCandidates,
  });

  final String token;
  final String receiverDeviceId;
  final String receiverDeviceName;
  final String receiverDeviceType;
  final int receiverPort;
  final String version;
  final String ssid;
  final String password;
  final String hostIp;
  final List<String> hostIpCandidates;
  final Completer<bool> _decision = Completer<bool>();

  Future<bool> get decision => _decision.future;

  DeviceInfo toDeviceInfo() {
    return DeviceInfo(
      deviceId: receiverDeviceId,
      deviceName: receiverDeviceName,
      deviceType: receiverDeviceType,
      ip: hostIp,
      port: receiverPort,
      version: version,
      lastSeen: DateTime.now(),
    );
  }

  void accept() {
    if (!_decision.isCompleted) {
      _decision.complete(true);
    }
  }

  void reject() {
    if (!_decision.isCompleted) {
      _decision.complete(false);
    }
  }
}

class TcpServerService {
  TcpServerService({
    required SettingsService settingsService,
    required HistoryService historyService,
  })  : _settingsService = settingsService,
        _historyService = historyService;

  final SettingsService _settingsService;
  final HistoryService _historyService;

  ServerSocket? _server;
  StreamSubscription<Socket>? _serverSubscription;

  final StreamController<IncomingTransferRequest> _requestController =
      StreamController<IncomingTransferRequest>.broadcast();
  final StreamController<HotspotJoinRequest> _hotspotJoinController =
      StreamController<HotspotJoinRequest>.broadcast();
  final StreamController<ReceiverHotspotReadyRequest>
      _receiverHotspotReadyController =
      StreamController<ReceiverHotspotReadyRequest>.broadcast();
  final StreamController<TransferTask> _taskController =
      StreamController<TransferTask>.broadcast();

  Stream<IncomingTransferRequest> get incomingRequests =>
      _requestController.stream;
  Stream<HotspotJoinRequest> get hotspotJoinRequests =>
      _hotspotJoinController.stream;
  Stream<ReceiverHotspotReadyRequest> get receiverHotspotReadyRequests =>
      _receiverHotspotReadyController.stream;
  Stream<TransferTask> get taskEvents => _taskController.stream;

  Future<void> start() async {
    _server = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      TransferProtocol.tcpPort,
    );
    _serverSubscription = _server?.listen(_handleSocket);
  }

  Future<void> stop() async {
    await _serverSubscription?.cancel();
    await _server?.close();
    _server = null;
  }

  Future<void> dispose() async {
    await stop();
    await _requestController.close();
    await _hotspotJoinController.close();
    await _receiverHotspotReadyController.close();
    await _taskController.close();
  }

  Future<void> _handleSocket(Socket socket) async {
    final reader = SocketReader(socket);
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
      final firstMessage = await TransferProtocol.readJson(reader).timeout(
        const Duration(seconds: 30),
      );

      if (firstMessage['type'] == 'hotspot_join') {
        await _handleHotspotJoin(socket, firstMessage);
        return;
      }

      if (firstMessage['type'] == 'receiver_hotspot_ready') {
        await _handleReceiverHotspotReady(socket, firstMessage);
        return;
      }

      if (firstMessage['type'] != 'transfer_request') {
        throw const FormatException(
          'Expected transfer_request, hotspot_join, or receiver_hotspot_ready.',
        );
      }

      final request = IncomingTransferRequest(
        taskId: firstMessage['taskId'] as String,
        senderDeviceId: firstMessage['senderDeviceId'] as String? ?? '',
        senderDeviceName: firstMessage['senderDeviceName'] as String? ?? 'Unknown',
        files: (firstMessage['files'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => TransferFile.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );

      _requestController.add(request);
      final accepted = await request.decision.timeout(
        const Duration(minutes: 2),
        onTimeout: () => false,
      );

      if (!accepted) {
        await TransferProtocol.writeJson(socket, {
          'type': 'transfer_reject',
          'taskId': request.taskId,
          'reason': 'user_rejected',
        });
        await _recordHistory(request, TransferStatus.rejected);
        return;
      }

      await TransferProtocol.writeJson(socket, {
        'type': 'transfer_accept',
        'taskId': request.taskId,
      });
      await _receiveFiles(socket, reader, request);
    } catch (_) {
      socket.destroy();
    } finally {
      await reader.cancel();
      await socket.close();
    }
  }

  Future<void> _handleHotspotJoin(
    Socket socket,
    Map<String, dynamic> message,
  ) async {
    final request = HotspotJoinRequest(
      token: message['token'] as String? ?? '',
      receiverDeviceId: message['receiverDeviceId'] as String? ?? '',
      receiverDeviceName: message['receiverDeviceName'] as String? ?? 'Receiver',
      receiverDeviceType: message['receiverDeviceType'] as String? ?? 'desktop',
      receiverIp: socket.remoteAddress.address,
      receiverPort: (message['receiverPort'] as num?)?.toInt() ??
          TransferProtocol.tcpPort,
      version: message['version'] as String? ?? TransferProtocol.appVersion,
    );

    _hotspotJoinController.add(request);
    final accepted = await request.decision.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );

    await TransferProtocol.writeJson(socket, {
      'type': 'hotspot_join_ack',
      'status': accepted ? 'accepted' : 'rejected',
      if (!accepted) 'reason': 'invalid_or_expired_token',
    });
  }

  Future<void> _handleReceiverHotspotReady(
    Socket socket,
    Map<String, dynamic> message,
  ) async {
    final request = ReceiverHotspotReadyRequest(
      token: message['token'] as String? ?? '',
      receiverDeviceId: message['receiverDeviceId'] as String? ?? '',
      receiverDeviceName: message['receiverDeviceName'] as String? ?? 'Receiver',
      receiverDeviceType: message['receiverDeviceType'] as String? ?? 'mobile',
      receiverPort: (message['receiverPort'] as num?)?.toInt() ??
          TransferProtocol.tcpPort,
      version: message['version'] as String? ?? TransferProtocol.appVersion,
      ssid: message['ssid'] as String? ?? '',
      password: message['password'] as String? ?? '',
      hostIp: message['hostIp'] as String? ?? '',
      hostIpCandidates: (message['hostIpCandidates'] as List? ?? const [])
          .whereType<String>()
          .toList(),
    );

    _receiverHotspotReadyController.add(request);
    final accepted = await request.decision.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );

    await TransferProtocol.writeJson(socket, {
      'type': 'receiver_hotspot_ack',
      'status': accepted ? 'accepted' : 'rejected',
      if (!accepted) 'reason': 'invalid_or_expired_token',
    });
  }

  Future<void> _receiveFiles(
    Socket socket,
    SocketReader reader,
    IncomingTransferRequest request,
  ) async {
    final saveDirectory = await _settingsService.getSaveDirectory();
    final now = DateTime.now();
    var task = TransferTask(
      taskId: request.taskId,
      direction: TransferDirection.receive,
      peerDeviceName: request.senderDeviceName,
      files: request.files,
      status: TransferStatus.transferring,
      totalBytes: request.totalBytes,
      transferredBytes: 0,
      currentFileName: request.files.isEmpty ? null : request.files.first.fileName,
      createdAt: now,
      updatedAt: now,
      savePath: saveDirectory.path,
    );
    _emitTask(task);

    final savedFiles = <TransferFile>[];
    var transferred = 0;
    var lastEmit = DateTime.now();

    try {
      for (var index = 0; index < request.files.length; index += 1) {
        final startMessage = await TransferProtocol.readJson(reader);
        if (startMessage['type'] != 'file_start') {
          throw const FormatException('Expected file_start.');
        }

        final announced = TransferFile.fromJson(startMessage);
        final expected = request.files[index];
        final file = announced.copyWith(
          fileName: announced.fileName.isEmpty ? expected.fileName : announced.fileName,
          fileSize: announced.fileSize == 0 ? expected.fileSize : announced.fileSize,
          sha256: announced.sha256.isEmpty ? expected.sha256 : announced.sha256,
        );

        final target = await FileNameService.uniqueFile(
          saveDirectory,
          file.fileName,
        );
        final partFile = File('${target.path}.part');
        if (await partFile.exists()) {
          await partFile.delete();
        }

        final output = partFile.openWrite();
        final digestSink = AccumulatorSink<Digest>();
        final hashInput = sha256.startChunkedConversion(digestSink);
        var remaining = file.fileSize;

        try {
          while (remaining > 0) {
            final chunk = await reader.readUpTo(
              min(TransferProtocol.chunkSize, remaining),
            );
            output.add(chunk);
            hashInput.add(chunk);
            remaining -= chunk.length;
            transferred += chunk.length;

            final now = DateTime.now();
            if (now.difference(lastEmit).inMilliseconds >= 120 || remaining == 0) {
              task = task.copyWith(
                transferredBytes: transferred,
                currentFileName: file.fileName,
                status: TransferStatus.transferring,
                clearError: true,
              );
              _emitTask(task);
              lastEmit = now;
            }
          }
        } finally {
          await output.flush();
          await output.close();
          hashInput.close();
        }

        final actualSha = digestSink.events.single.toString();
        if (file.sha256.isNotEmpty && actualSha != file.sha256) {
          if (await partFile.exists()) {
            await partFile.delete();
          }
          throw FileSystemException('SHA-256 mismatch', file.fileName);
        }

        final saved = await partFile.rename(target.path);
        final savedFile = file.copyWith(
          sha256: actualSha,
          savePath: saved.path,
        );
        savedFiles.add(savedFile);

        await TransferProtocol.writeJson(socket, {
          'type': 'file_received',
          'taskId': request.taskId,
          'fileName': savedFile.fileName,
          'status': 'success',
        });
      }

      final complete = await TransferProtocol.readJson(reader);
      if (complete['type'] != 'transfer_complete') {
        throw const FormatException('Expected transfer_complete.');
      }

      task = task.copyWith(
        files: savedFiles,
        status: TransferStatus.completed,
        transferredBytes: task.totalBytes,
        currentFileName: savedFiles.isEmpty ? task.currentFileName : savedFiles.last.fileName,
        savePath: saveDirectory.path,
      );
      await _recordCompletedReceiveHistory(task);
      _emitTask(task);
    } catch (error) {
      task = task.copyWith(
        status: TransferStatus.failed,
        errorMessage: error.toString(),
      );
      await _recordHistory(request, TransferStatus.failed);
      _emitTask(task);
      rethrow;
    }
  }

  Future<void> _recordHistory(
    IncomingTransferRequest request,
    TransferStatus status,
  ) async {
    await _historyService.addRecords(
      request.files.map(
        (file) => TransferHistoryRecord(
          taskId: request.taskId,
          direction: TransferDirection.receive,
          peerDeviceName: request.senderDeviceName,
          fileName: file.fileName,
          fileSize: file.fileSize,
          status: status,
          createdAt: DateTime.now(),
        ),
      ),
    );
  }

  Future<void> _recordCompletedReceiveHistory(TransferTask task) async {
    await _historyService.addRecords(
      task.files.map(
        (file) => TransferHistoryRecord(
          taskId: task.taskId,
          direction: TransferDirection.receive,
          peerDeviceName: task.peerDeviceName,
          fileName: file.fileName,
          fileSize: file.fileSize,
          status: TransferStatus.completed,
          savePath: file.savePath,
          createdAt: DateTime.now(),
        ),
      ),
    );
  }

  void _emitTask(TransferTask task) {
    if (!_taskController.isClosed) {
      _taskController.add(task);
    }
  }
}
