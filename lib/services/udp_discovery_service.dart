import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/device_info.dart';
import 'protocol.dart';

class UdpDiscoveryService {
  UdpDiscoveryService({DiscoveryPlatformService? platformService})
      : _platformService = platformService ?? DiscoveryPlatformService();

  final DiscoveryPlatformService _platformService;
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _pruneTimer;
  StreamSubscription<RawSocketEvent>? _subscription;
  DeviceInfo? _localDevice;
  bool _multicastLockActive = false;

  final Map<String, DeviceInfo> _devices = {};
  final StreamController<List<DeviceInfo>> _devicesController =
      StreamController<List<DeviceInfo>>.broadcast();

  Stream<List<DeviceInfo>> get devices => _devicesController.stream;

  Future<void> start(DeviceInfo localDevice) async {
    _localDevice = localDevice;
    await _acquireAndroidMulticastLock();
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        TransferProtocol.udpPort,
        reuseAddress: true,
      );
    } catch (_) {
      await _releaseAndroidMulticastLock();
      rethrow;
    }
    _socket?.broadcastEnabled = true;
    _subscription = _socket?.listen(_handleSocketEvent);

    _broadcast();
    _broadcastTimer = Timer.periodic(
      TransferProtocol.broadcastInterval,
      (_) => _broadcast(),
    );
    _pruneTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pruneOfflineDevices(),
    );
  }

  void updateLocalDevice(DeviceInfo localDevice) {
    _localDevice = localDevice;
    _broadcast();
  }

  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _pruneTimer?.cancel();
    await _subscription?.cancel();
    _socket?.close();
    _socket = null;
    await _releaseAndroidMulticastLock();
    _devices.clear();
    _emitDevices();
  }

  Future<void> dispose() async {
    await stop();
    await _devicesController.close();
  }

  void _broadcast() {
    final socket = _socket;
    final localDevice = _localDevice;
    if (socket == null || localDevice == null) {
      return;
    }

    final payload = utf8.encode(jsonEncode(localDevice.toAnnounceJson()));
    for (final target in _broadcastTargets(localDevice.ip)) {
      try {
        socket.send(payload, target, TransferProtocol.udpPort);
      } catch (_) {
        continue;
      }
    }
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }

    Datagram? datagram;
    while ((datagram = _socket?.receive()) != null) {
      try {
        final decoded = jsonDecode(utf8.decode(datagram!.data));
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        if (decoded['type'] != 'device_announce') {
          continue;
        }

        final device = DeviceInfo.fromAnnounceJson(
          decoded,
          fallbackIp: datagram.address.address,
        );
        if (device.deviceId == _localDevice?.deviceId) {
          continue;
        }

        _devices[device.deviceId] = device;
        _emitDevices();
      } catch (_) {
        continue;
      }
    }
  }

  void _pruneOfflineDevices() {
    final before = _devices.length;
    _devices.removeWhere(
      (_, device) => !device.isOnline(TransferProtocol.offlineAfter),
    );
    if (_devices.length != before) {
      _emitDevices();
    }
  }

  void _emitDevices() {
    final list = _devices.values.toList()
      ..sort((a, b) => a.deviceName.compareTo(b.deviceName));
    if (!_devicesController.isClosed) {
      _devicesController.add(list);
    }
  }

  List<InternetAddress> _broadcastTargets(String localIp) {
    final targets = <String>{'255.255.255.255'};
    final parts = localIp.split('.');
    if (parts.length == 4 && parts.every((part) => int.tryParse(part) != null)) {
      targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
    }
    return targets.map((target) => InternetAddress(target)).toList();
  }

  Future<void> _acquireAndroidMulticastLock() async {
    if (!Platform.isAndroid || _multicastLockActive) {
      return;
    }
    try {
      await _platformService.acquireMulticastLock();
      _multicastLockActive = true;
    } on MissingPluginException {
      return;
    } catch (_) {
      return;
    }
  }

  Future<void> _releaseAndroidMulticastLock() async {
    if (!Platform.isAndroid || !_multicastLockActive) {
      return;
    }
    _multicastLockActive = false;
    try {
      await _platformService.releaseMulticastLock();
    } on MissingPluginException {
      return;
    } catch (_) {
      return;
    }
  }
}

class DiscoveryPlatformService {
  static const MethodChannel _channel = MethodChannel('maoqiu_transfer/hotspot');

  Future<void> acquireMulticastLock() async {
    await _channel.invokeMethod<void>('acquireMulticastLock');
  }

  Future<void> releaseMulticastLock() async {
    await _channel.invokeMethod<void>('releaseMulticastLock');
  }
}
