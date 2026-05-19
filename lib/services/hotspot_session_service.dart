import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../models/connection_invite.dart';
import '../models/device_info.dart';
import '../models/transfer_file.dart';
import 'protocol.dart';

class HotspotSessionService {
  HotspotSessionService({HotspotPlatformService? platformService})
      : _platformService = platformService ?? HotspotPlatformService();

  final HotspotPlatformService _platformService;
  final Random _random = Random.secure();
  final Uuid _uuid = const Uuid();

  Future<HotspotSession> createSession({
    required DeviceInfo localDevice,
    required List<TransferFile> files,
  }) async {
    final suffix = _hex(4);
    var ssid = 'MaoQiu-Transfer-$suffix';
    var password = 'mq-${_digits(4)}-${_digits(4)}';
    var hostIp = localDevice.ip;
    var nativeHotspotActive = false;
    var platformMessage = '当前平台未创建系统热点，请让接收端加入同一网络后扫码继续。';

    if (Platform.isAndroid) {
      try {
        await _ensureAndroidHotspotPermissions();
        final result = await _platformService.startLocalOnlyHotspot(
          suggestedSsid: ssid,
          suggestedPassword: password,
        );
        ssid = result.ssid.isEmpty ? ssid : result.ssid;
        password = result.password.isEmpty ? password : result.password;
        hostIp = result.hostIp.isEmpty ? hostIp : result.hostIp;
        nativeHotspotActive = true;
        platformMessage = '已创建仅本地通信的临时热点。';
      } on MissingPluginException {
        platformMessage = 'Android 热点原生通道尚未接入，已生成可手动加入的邀请二维码。';
      } catch (error) {
        platformMessage = '自动创建热点失败：$error';
      }
    }

    return HotspotSession(
      invite: HotspotInvite(
        ssid: ssid,
        password: password,
        hostIp: hostIp,
        port: TransferProtocol.tcpPort,
        token: _uuid.v4(),
        expireAt: DateTime.now().add(const Duration(minutes: 5)),
      ),
      files: List.unmodifiable(files),
      createdAt: DateTime.now(),
      nativeHotspotActive: nativeHotspotActive,
      platformMessage: platformMessage,
    );
  }

  Future<void> stopSession(HotspotSession? session) async {
    if (session?.nativeHotspotActive != true) {
      return;
    }
    try {
      await _platformService.stopLocalOnlyHotspot();
    } catch (_) {
      return;
    }
  }

  Future<void> _ensureAndroidHotspotPermissions() async {
    final locationStatus = await Permission.locationWhenInUse.request();
    if (!locationStatus.isGranted) {
      throw StateError('Android 创建临时热点需要允许附近设备 / 位置信息权限。');
    }
  }

  String _hex(int length) {
    const chars = '0123456789ABCDEF';
    return List.generate(length, (_) => chars[_random.nextInt(chars.length)])
        .join();
  }

  String _digits(int length) {
    return List.generate(length, (_) => _random.nextInt(10).toString()).join();
  }
}

class PlatformHotspotResult {
  const PlatformHotspotResult({
    required this.ssid,
    required this.password,
    required this.hostIp,
  });

  final String ssid;
  final String password;
  final String hostIp;
}

class HotspotPlatformService {
  static const MethodChannel _channel = MethodChannel('maoqiu_transfer/hotspot');

  Future<PlatformHotspotResult> startLocalOnlyHotspot({
    required String suggestedSsid,
    required String suggestedPassword,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'startLocalOnlyHotspot',
      {
        'suggestedSsid': suggestedSsid,
        'suggestedPassword': suggestedPassword,
      },
    );

    return PlatformHotspotResult(
      ssid: result?['ssid'] as String? ?? suggestedSsid,
      password: result?['password'] as String? ?? suggestedPassword,
      hostIp: result?['hostIp'] as String? ?? '192.168.43.1',
    );
  }

  Future<void> stopLocalOnlyHotspot() async {
    await _channel.invokeMethod<void>('stopLocalOnlyHotspot');
  }
}
