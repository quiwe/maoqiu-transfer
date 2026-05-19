import 'dart:io';

import '../models/connection_invite.dart';
import '../models/device_info.dart';
import 'hotspot_session_service.dart';
import 'protocol.dart';

class HotspotJoinService {
  HotspotJoinService({HotspotPlatformService? platformService})
      : _platformService = platformService ?? HotspotPlatformService();

  final HotspotPlatformService _platformService;

  Future<void> announceReceiver({
    required HotspotInvite invite,
    required DeviceInfo localDevice,
  }) async {
    if (invite.isExpired) {
      throw StateError('邀请二维码已过期。');
    }

    if (Platform.isAndroid) {
      await _platformService.connectToWifi(
        ssid: invite.ssid,
        password: invite.password,
      );
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
}
