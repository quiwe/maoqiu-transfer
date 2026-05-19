import 'dart:convert';

class DeviceInfo {
  const DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.ip,
    required this.port,
    required this.version,
    required this.lastSeen,
  });

  final String deviceId;
  final String deviceName;
  final String deviceType;
  final String ip;
  final int port;
  final String version;
  final DateTime lastSeen;

  bool get isMobile => deviceType == 'mobile';

  bool isOnline(Duration offlineAfter) {
    return DateTime.now().difference(lastSeen) <= offlineAfter;
  }

  DeviceInfo copyWith({
    String? deviceId,
    String? deviceName,
    String? deviceType,
    String? ip,
    int? port,
    String? version,
    DateTime? lastSeen,
  }) {
    return DeviceInfo(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      deviceType: deviceType ?? this.deviceType,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      version: version ?? this.version,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  Map<String, dynamic> toAnnounceJson() {
    return {
      'type': 'device_announce',
      'deviceId': deviceId,
      'deviceName': deviceName,
      'deviceType': deviceType,
      'ip': ip,
      'port': port,
      'version': version,
    };
  }

  factory DeviceInfo.fromAnnounceJson(
    Map<String, dynamic> json, {
    String? fallbackIp,
  }) {
    return DeviceInfo(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String? ?? 'Unknown Device',
      deviceType: json['deviceType'] as String? ?? 'desktop',
      ip: json['ip'] as String? ?? fallbackIp ?? '',
      port: (json['port'] as num?)?.toInt() ?? 9527,
      version: json['version'] as String? ?? '0.2.0',
      lastSeen: DateTime.now(),
    );
  }

  @override
  String toString() => jsonEncode(toAnnounceJson());
}
