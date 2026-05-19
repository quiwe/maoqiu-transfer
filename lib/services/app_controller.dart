import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_update.dart';
import '../models/connection_invite.dart';
import '../models/device_info.dart';
import '../models/transfer_file.dart';
import '../models/transfer_task.dart';
import 'device_id_service.dart';
import 'file_sender_service.dart';
import 'hash_service.dart';
import 'hotspot_join_service.dart';
import 'github_update_service.dart';
import 'hotspot_session_service.dart';
import 'history_service.dart';
import 'network_info_service.dart';
import 'protocol.dart';
import 'settings_service.dart';
import 'tcp_server_service.dart';
import 'udp_discovery_service.dart';

class AppController extends ChangeNotifier {
  AppController() {
    _fileSenderService = FileSenderService(
      hashService: HashService(),
      historyService: _historyService,
    );
    _tcpServerService = TcpServerService(
      settingsService: _settingsService,
      historyService: _historyService,
    );
  }

  final DeviceIdService _deviceIdService = DeviceIdService();
  final NetworkInfoService _networkInfoService = NetworkInfoService();
  final SettingsService _settingsService = SettingsService();
  final HistoryService _historyService = HistoryService();
  final UdpDiscoveryService _udpDiscoveryService = UdpDiscoveryService();
  final HotspotSessionService _hotspotSessionService = HotspotSessionService();
  final HotspotJoinService _hotspotJoinService = HotspotJoinService();
  final GitHubUpdateService _updateService = GitHubUpdateService();
  late final TcpServerService _tcpServerService;
  late final FileSenderService _fileSenderService;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Map<String, TransferTask> _tasks = {};

  DeviceInfo? localDevice;
  HotspotSession? activeHotspotSession;
  String? activeHotspotTaskId;
  String? hotspotMessage;
  List<DeviceInfo> nearbyDevices = [];
  String? startupError;
  AppUpdateInfo? availableUpdate;
  UpdateDownloadState updateDownloadState = const UpdateDownloadState.idle();
  String? updateMessage;
  bool isCheckingUpdate = false;
  bool isStarted = false;

  SettingsService get settings => _settingsService;
  HistoryService get history => _historyService;
  Stream<IncomingTransferRequest> get incomingRequests =>
      _tcpServerService.incomingRequests;
  List<TransferTask> get transfers => _tasks.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> start() async {
    if (isStarted) {
      return;
    }

    try {
      await _settingsService.init();
      await _historyService.init();
      final deviceId = await _deviceIdService.getOrCreateDeviceId();
      final deviceName = await _networkInfoService.getDeviceName();
      final ip = await _networkInfoService.getLocalIp();

      localDevice = DeviceInfo(
        deviceId: deviceId,
        deviceName: deviceName,
        deviceType: _networkInfoService.getDeviceType(),
        ip: ip,
        port: TransferProtocol.tcpPort,
        version: TransferProtocol.appVersion,
        lastSeen: DateTime.now(),
      );

      await _tcpServerService.start();
      await _udpDiscoveryService.start(localDevice!);

      _subscriptions
        ..add(
          _udpDiscoveryService.devices.listen((devices) {
            nearbyDevices = devices;
            notifyListeners();
          }),
        )
        ..add(
          _tcpServerService.taskEvents.listen(_upsertTask),
        )
        ..add(
          _tcpServerService.hotspotJoinRequests.listen(_handleHotspotJoin),
        )
        ..add(
          _tcpServerService.receiverHotspotReadyRequests
              .listen(_handleReceiverHotspotReady),
        )
        ..add(
          _fileSenderService.taskEvents.listen(_upsertTask),
        );

      isStarted = true;
      startupError = null;
      notifyListeners();
      unawaited(checkForUpdates(silent: true));
    } catch (error) {
      startupError = error.toString();
      notifyListeners();
    }
  }

  Future<void> refreshLocalDevice() async {
    final current = localDevice;
    if (current == null) {
      return;
    }

    final ip = await _networkInfoService.getLocalIp();
    localDevice = current.copyWith(ip: ip, lastSeen: DateTime.now());
    _udpDiscoveryService.updateLocalDevice(localDevice!);
    notifyListeners();
  }

  String sendFiles(
    DeviceInfo peer,
    List<TransferFile> files, {
    List<String> peerIpCandidates = const [],
  }) {
    final local = localDevice;
    if (local == null) {
      throw StateError('Local device is not ready.');
    }
    return _fileSenderService.sendFiles(
      localDevice: local,
      peer: peer,
      files: files,
      peerIpCandidates: peerIpCandidates,
    );
  }

  Future<HotspotSession> createHotspotSession(List<TransferFile> files) async {
    final local = localDevice;
    if (local == null) {
      throw StateError('Local device is not ready.');
    }
    if (files.isEmpty) {
      throw ArgumentError('No files selected.');
    }

    await stopHotspotSession();
    final session = await _hotspotSessionService.createSession(
      localDevice: local,
      files: files,
    );
    activeHotspotSession = session;
    activeHotspotTaskId = null;
    hotspotMessage = session.platformMessage;
    notifyListeners();
    return session;
  }

  Future<void> stopHotspotSession() async {
    final session = activeHotspotSession;
    activeHotspotSession = null;
    activeHotspotTaskId = null;
    if (session != null) {
      await _hotspotSessionService.stopSession(session);
    }
    notifyListeners();
  }

  Future<void> joinHotspotInvite(HotspotInvite invite) async {
    await refreshLocalDevice();
    final local = localDevice;
    if (local == null) {
      throw StateError('Local device is not ready.');
    }
    await _hotspotJoinService.announceReceiver(
      invite: invite,
      localDevice: local,
    );
  }

  TransferTask? taskById(String taskId) => _tasks[taskId];

  Future<void> setSaveDirectory(String path) async {
    await _settingsService.setSaveDirectory(path);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await _historyService.clear();
    notifyListeners();
  }

  Future<void> checkForUpdates({bool silent = false}) async {
    if (isCheckingUpdate) {
      return;
    }

    isCheckingUpdate = true;
    if (!silent) {
      updateMessage = '正在检查更新...';
      updateDownloadState = const UpdateDownloadState.idle();
      notifyListeners();
    }

    try {
      final update = await _updateService.checkForUpdate();
      availableUpdate = update;
      if (update == null) {
        if (!silent) {
          updateMessage = '当前已是最新版本。';
        }
      } else {
        updateMessage = '发现新版本 ${update.version}。';
      }
    } catch (error) {
      if (!silent) {
        updateMessage = error.toString();
      }
    } finally {
      isCheckingUpdate = false;
      notifyListeners();
    }
  }

  Future<void> downloadAvailableUpdate() async {
    var update = availableUpdate;
    if (update == null) {
      await checkForUpdates();
      update = availableUpdate;
    }
    if (update == null || updateDownloadState.isDownloading) {
      return;
    }

    await for (final state in _updateService.downloadUpdate(update)) {
      updateDownloadState = state;
      switch (state.status) {
        case UpdateDownloadStatus.idle:
          updateMessage = null;
          break;
        case UpdateDownloadStatus.downloading:
          updateMessage = '正在下载 ${update.assetName}...';
          break;
        case UpdateDownloadStatus.downloaded:
          updateMessage = '下载完成。';
          break;
        case UpdateDownloadStatus.failed:
          updateMessage = state.errorMessage ?? '下载失败。';
          break;
      }
      notifyListeners();
    }
  }

  void _upsertTask(TransferTask task) {
    _tasks[task.taskId] = task;
    if (task.taskId == activeHotspotTaskId && _isTerminal(task.status)) {
      unawaited(stopHotspotSession());
      unawaited(_hotspotJoinService.cleanupTransientNetwork());
    }
    if (task.direction == TransferDirection.receive && _isTerminal(task.status)) {
      unawaited(_hotspotJoinService.cleanupTransientNetwork());
    }
    notifyListeners();
  }

  void _handleHotspotJoin(HotspotJoinRequest request) {
    final session = activeHotspotSession;
    if (session == null ||
        session.isExpired ||
        request.token != session.invite.token ||
        session.files.isEmpty) {
      request.reject();
      hotspotMessage = '收到无效或过期的热点加入请求。';
      notifyListeners();
      return;
    }

    request.accept();
    final taskId = sendFiles(request.toDeviceInfo(), session.files);
    activeHotspotTaskId = taskId;
    hotspotMessage = '${request.receiverDeviceName} 已加入，正在发起传输确认。';
    notifyListeners();
  }

  void _handleReceiverHotspotReady(ReceiverHotspotReadyRequest request) {
    final session = activeHotspotSession;
    if (session == null ||
        session.isExpired ||
        request.token != session.invite.token ||
        !session.invite.usesReceiverHotspot ||
        session.files.isEmpty ||
        request.ssid.isEmpty) {
      request.reject();
      hotspotMessage = '收到无效或过期的扫码热点请求。';
      notifyListeners();
      return;
    }

    request.accept();
    hotspotMessage = '${request.receiverDeviceName} 已开启热点，正在连接 ${request.ssid}。';
    notifyListeners();
    unawaited(_connectReceiverHotspotAndSend(request, session));
  }

  Future<void> _connectReceiverHotspotAndSend(
    ReceiverHotspotReadyRequest request,
    HotspotSession session,
  ) async {
    try {
      await _hotspotJoinService.connectToWifi(
        ssid: request.ssid,
        password: request.password,
      );
      if (activeHotspotSession?.invite.token != session.invite.token) {
        return;
      }
      await refreshLocalDevice();
      final taskId = sendFiles(
        request.toDeviceInfo(),
        session.files,
        peerIpCandidates: request.hostIpCandidates,
      );
      activeHotspotTaskId = taskId;
      hotspotMessage = '已连接 ${request.ssid}，正在向 ${request.receiverDeviceName} 发送文件。';
    } catch (error) {
      if (activeHotspotSession?.invite.token != session.invite.token) {
        return;
      }
      hotspotMessage = '连接手机热点失败：$error';
    }
    notifyListeners();
  }

  bool _isTerminal(TransferStatus status) {
    return status == TransferStatus.completed ||
        status == TransferStatus.failed ||
        status == TransferStatus.rejected ||
        status == TransferStatus.cancelled;
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_udpDiscoveryService.dispose());
    unawaited(_tcpServerService.dispose());
    unawaited(_fileSenderService.dispose());
    unawaited(_hotspotSessionService.stopSession(activeHotspotSession));
    unawaited(_hotspotJoinService.cleanupTransientNetwork());
    _updateService.dispose();
    super.dispose();
  }
}
