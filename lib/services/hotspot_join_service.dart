import 'dart:io';

import '../models/connection_invite.dart';
import '../models/device_info.dart';
import 'protocol.dart';

class HotspotJoinService {
  Future<void> announceReceiver({
    required HotspotInvite invite,
    required DeviceInfo localDevice,
  }) async {
    if (invite.isExpired) {
      throw StateError('邀请二维码已过期。');
    }

    final socket = await Socket.connect(
      invite.hostIp,
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
}
