import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import '../models/connection_invite.dart';
import '../models/device_info.dart';
import 'hotspot_session_service.dart';
import 'protocol.dart';

class HotspotJoinService {
  HotspotJoinService({HotspotPlatformService? platformService})
      : _platformService = platformService ?? HotspotPlatformService();

  final HotspotPlatformService _platformService;
  bool _receiverHotspotActive = false;
  bool _joinedSenderWifi = false;

  Future<void> announceReceiver({
    required HotspotInvite invite,
    required DeviceInfo localDevice,
  }) async {
    if (invite.isExpired) {
      throw StateError('邀请二维码已过期。');
    }

    if (invite.usesReceiverHotspot) {
      await _startReceiverHotspotAndNotifySender(
        invite: invite,
        localDevice: localDevice,
      );
      return;
    }

    if (Platform.isAndroid) {
      await _platformService.connectToWifi(
        ssid: invite.ssid,
        password: invite.password,
      );
      _joinedSenderWifi = true;
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    Object? lastError;
    for (final hostIp in _hostIpCandidates(invite.hostIp)) {
      try {
        await _announceToHost(
          invite: invite,
          localDevice: localDevice,
          hostIp: hostIp,
        );
        return;
      } catch (error) {
        lastError = error;
      }
    }

    throw StateError('已加入 Wi-Fi，但无法连接发送端：$lastError');
  }

  Future<void> connectToWifi({
    required String ssid,
    required String password,
  }) async {
    await _platformService.connectToWifi(ssid: ssid, password: password);
    if (Platform.isAndroid) {
      _joinedSenderWifi = true;
    }
    await Future<void>.delayed(const Duration(seconds: 3));
  }

  Future<void> cleanupTransientNetwork() async {
    if (_receiverHotspotActive) {
      await stopReceiverHotspot();
    }
    if (_joinedSenderWifi) {
      _joinedSenderWifi = false;
      await _platformService.releaseWifiNetwork();
    }
  }

  Future<void> stopReceiverHotspot() async {
    if (!_receiverHotspotActive) {
      return;
    }
    _receiverHotspotActive = false;
    try {
      await _platformService.stopLocalOnlyHotspot();
    } catch (_) {
      return;
    }
  }

  Future<void> _startReceiverHotspotAndNotifySender({
    required HotspotInvite invite,
    required DeviceInfo localDevice,
  }) async {
    if (!Platform.isAndroid) {
      throw StateError('这个二维码需要用 Android 手机扫码并创建临时热点。');
    }

    await _ensureAndroidHotspotPermissions();
    final hotspot = await _platformService.startLocalOnlyHotspot(
      suggestedSsid: 'MaoQiu-Receiver',
      suggestedPassword: 'maoqiu-transfer',
    );
    _receiverHotspotActive = true;

    try {
      await _announceReceiverHotspotReady(
        invite: invite,
        localDevice: localDevice,
        hotspot: hotspot,
      );
    } catch (_) {
      await stopReceiverHotspot();
      rethrow;
    }
  }

  Future<void> _announceReceiverHotspotReady({
    required HotspotInvite invite,
    required DeviceInfo localDevice,
    required PlatformHotspotResult hotspot,
  }) async {
    Object? lastError;
    for (final hostIp in _hostIpCandidates(invite.hostIp)) {
      try {
        await _sendReceiverHotspotReady(
          invite: invite,
          localDevice: localDevice,
          hotspot: hotspot,
          hostIp: hostIp,
        );
        return;
      } catch (error) {
        lastError = error;
      }
    }

    throw StateError('手机热点已开启，但无法通知发送端：$lastError');
  }

  Future<void> _sendReceiverHotspotReady({
    required HotspotInvite invite,
    required DeviceInfo localDevice,
    required PlatformHotspotResult hotspot,
    required String hostIp,
  }) async {
    final socket = await Socket.connect(
      hostIp,
      invite.port,
      timeout: const Duration(seconds: 8),
    );
    final reader = SocketReader(socket);

    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
      await TransferProtocol.writeJson(socket, {
        'type': 'receiver_hotspot_ready',
        'token': invite.token,
        'receiverDeviceId': localDevice.deviceId,
        'receiverDeviceName': localDevice.deviceName,
        'receiverDeviceType': localDevice.deviceType,
        'receiverPort': localDevice.port,
        'version': localDevice.version,
        'ssid': hotspot.ssid,
        'password': hotspot.password,
        'hostIp': hotspot.hostIp,
        'hostIpCandidates': _receiverHostIpCandidates(hotspot.hostIp),
      });

      final response = await TransferProtocol.readJson(reader);
      if (response['type'] != 'receiver_hotspot_ack' ||
          response['status'] != 'accepted') {
        throw StateError(response['reason'] as String? ?? '发送端拒绝了连接。');
      }
    } finally {
      await reader.cancel();
      await socket.close();
    }
  }

  Future<void> _announceToHost({
    required HotspotInvite invite,
    required DeviceInfo localDevice,
    required String hostIp,
  }) async {
    final socket = await Socket.connect(
      hostIp,
      invite.port,
      timeout: const Duration(seconds: 8),
    );
    final reader = SocketReader(socket);

    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
      await TransferProtocol.writeJson(socket, {
        'type': 'hotspot_join',
        'token': invite.token,
        'receiverDeviceId': localDevice.deviceId,
        'receiverDeviceName': localDevice.deviceName,
        'receiverDeviceType': localDevice.deviceType,
        'receiverPort': localDevice.port,
        'version': localDevice.version,
      });

      final response = await TransferProtocol.readJson(reader);
      if (response['type'] != 'hotspot_join_ack' ||
          response['status'] != 'accepted') {
        throw StateError(response['reason'] as String? ?? '发送端拒绝了连接。');
      }
    } finally {
      await reader.cancel();
      await socket.close();
    }
  }

  List<String> _hostIpCandidates(String hostIp) {
    return <String>{
      if (hostIp.trim().isNotEmpty) hostIp.trim(),
      '192.168.43.1',
      '192.168.49.1',
      '192.168.137.1',
    }.toList();
  }

  List<String> _receiverHostIpCandidates(String hostIp) {
    return <String>{
      if (hostIp.trim().isNotEmpty) hostIp.trim(),
      '192.168.43.1',
      '192.168.49.1',
      '192.168.137.1',
      '172.20.10.1',
    }.toList();
  }

  Future<void> _ensureAndroidHotspotPermissions() async {
    final nearbyStatus = await Permission.nearbyWifiDevices.request();
    if (nearbyStatus.isGranted) {
      return;
    }

    final locationStatus = await Permission.locationWhenInUse.request();
    if (!locationStatus.isGranted && !nearbyStatus.isGranted) {
      throw StateError('Android 创建临时热点需要允许附近设备或位置信息权限。');
    }
  }
}
