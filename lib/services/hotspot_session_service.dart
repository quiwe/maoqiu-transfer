import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/connection_invite.dart';
import '../models/device_info.dart';
import '../models/transfer_file.dart';
import 'protocol.dart';

class HotspotSessionService {
  HotspotSessionService({HotspotPlatformService? platformService})
      : _platformService = platformService ?? HotspotPlatformService();

  final HotspotPlatformService _platformService;
  final Uuid _uuid = const Uuid();

  Future<HotspotSession> createSession({
    required DeviceInfo localDevice,
    required List<TransferFile> files,
  }) async {
    return HotspotSession(
      invite: HotspotInvite(
        ssid: '',
        password: '',
        hostIp: localDevice.ip,
        port: TransferProtocol.tcpPort,
        token: _uuid.v4(),
        expireAt: DateTime.now().add(const Duration(minutes: 5)),
        hotspotOwner: HotspotOwner.receiver,
      ),
      files: List.unmodifiable(files),
      createdAt: DateTime.now(),
      nativeHotspotActive: false,
      platformMessage: '请用手机扫码。手机会开启临时热点，本机随后自动连接并发送文件。',
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

  Future<bool> connectToWifi({
    required String ssid,
    required String password,
  }) async {
    if (Platform.isWindows) {
      return _connectToWifiOnWindows(ssid: ssid, password: password);
    }
    if (Platform.isMacOS) {
      return _connectToWifiOnMacOS(ssid: ssid, password: password);
    }
    if (Platform.isLinux) {
      return _connectToWifiOnLinux(ssid: ssid, password: password);
    }

    final connected = await _channel.invokeMethod<bool>(
      'connectToWifi',
      {
        'ssid': ssid,
        'password': password,
      },
    );
    return connected ?? false;
  }

  Future<void> releaseWifiNetwork() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('releaseWifiNetwork');
    }
  }

  Future<bool> _connectToWifiOnWindows({
    required String ssid,
    required String password,
  }) async {
    final temp = await Directory.systemTemp.createTemp('maoqiu-wifi-');
    final profile = File('${temp.path}${Platform.pathSeparator}wifi.xml');
    try {
      await profile.writeAsString(
        _windowsWifiProfile(ssid: ssid, password: password),
      );
      final add = await Process.run(
        'netsh',
        ['wlan', 'add', 'profile', 'filename=${profile.path}', 'user=current'],
      );
      if (add.exitCode != 0) {
        throw StateError(_processError(add));
      }

      final connect = await Process.run(
        'netsh',
        ['wlan', 'connect', 'name=$ssid', 'ssid=$ssid'],
      );
      if (connect.exitCode != 0) {
        throw StateError(_processError(connect));
      }
      return true;
    } finally {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  }

  Future<bool> _connectToWifiOnMacOS({
    required String ssid,
    required String password,
  }) async {
    final device = await _macOSWifiDevice();
    final result = await Process.run(
      'networksetup',
      ['-setairportnetwork', device, ssid, password],
    );
    if (result.exitCode != 0) {
      throw StateError(_processError(result));
    }
    return true;
  }

  Future<String> _macOSWifiDevice() async {
    final result = await Process.run('networksetup', ['-listallhardwareports']);
    if (result.exitCode != 0) {
      throw StateError(_processError(result));
    }

    final lines = (result.stdout as String).split(RegExp(r'\r?\n'));
    for (var index = 0; index < lines.length; index += 1) {
      if (!lines[index].contains('Hardware Port: Wi-Fi') &&
          !lines[index].contains('Hardware Port: AirPort')) {
        continue;
      }
      for (var next = index + 1; next < lines.length; next += 1) {
        final line = lines[next].trim();
        if (line.startsWith('Device:')) {
          return line.substring('Device:'.length).trim();
        }
      }
    }
    throw StateError('未找到 macOS Wi-Fi 网卡。');
  }

  Future<bool> _connectToWifiOnLinux({
    required String ssid,
    required String password,
  }) async {
    final result = await Process.run(
      'nmcli',
      ['dev', 'wifi', 'connect', ssid, 'password', password],
    );
    if (result.exitCode != 0) {
      throw StateError(_processError(result));
    }
    return true;
  }

  String _windowsWifiProfile({
    required String ssid,
    required String password,
  }) {
    final escapedSsid = _xmlEscape(ssid);
    final escapedPassword = _xmlEscape(password);
    final ssidHex = utf8.encode(ssid).map((byte) {
      return byte.toRadixString(16).padLeft(2, '0').toUpperCase();
    }).join();

    return '''
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>$escapedSsid</name>
  <SSIDConfig>
    <SSID>
      <hex>$ssidHex</hex>
      <name>$escapedSsid</name>
    </SSID>
  </SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>manual</connectionMode>
  <MSM>
    <security>
      <authEncryption>
        <authentication>WPA2PSK</authentication>
        <encryption>AES</encryption>
        <useOneX>false</useOneX>
      </authEncryption>
      <sharedKey>
        <keyType>passPhrase</keyType>
        <protected>false</protected>
        <keyMaterial>$escapedPassword</keyMaterial>
      </sharedKey>
    </security>
  </MSM>
</WLANProfile>
''';
  }

  String _xmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  String _processError(ProcessResult result) {
    final stderr = result.stderr.toString().trim();
    final stdout = result.stdout.toString().trim();
    return stderr.isNotEmpty ? stderr : stdout;
  }
}
