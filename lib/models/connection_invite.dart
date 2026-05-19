import 'dart:convert';

import 'transfer_file.dart';

enum HotspotOwner {
  sender('sender'),
  receiver('receiver');

  const HotspotOwner(this.value);

  final String value;

  static HotspotOwner parse(String? value) {
    return HotspotOwner.values.firstWhere(
      (item) => item.value == value,
      orElse: () => HotspotOwner.sender,
    );
  }
}

class HotspotInvite {
  const HotspotInvite({
    required this.ssid,
    required this.password,
    required this.hostIp,
    required this.port,
    required this.token,
    required this.expireAt,
    this.hotspotOwner = HotspotOwner.sender,
  });

  final String ssid;
  final String password;
  final String hostIp;
  final int port;
  final String token;
  final DateTime expireAt;
  final HotspotOwner hotspotOwner;

  bool get isExpired => DateTime.now().isAfter(expireAt);
  bool get usesReceiverHotspot => hotspotOwner == HotspotOwner.receiver;

  Map<String, dynamic> toJson() {
    return {
      'mode': 'hotspot',
      'hotspotOwner': hotspotOwner.value,
      'ssid': ssid,
      'password': password,
      'hostIp': hostIp,
      'port': port,
      'token': token,
      'expireAt': expireAt.toIso8601String(),
    };
  }

  String toQrPayload() => jsonEncode(toJson());

  factory HotspotInvite.fromQrPayload(String raw) {
    final decoded = jsonDecode(raw.trim());
    if (decoded is! Map<String, dynamic> || decoded['mode'] != 'hotspot') {
      throw const FormatException('二维码内容不是毛球互传热点邀请。');
    }

    return HotspotInvite(
      ssid: decoded['ssid'] as String? ?? '',
      password: decoded['password'] as String? ?? '',
      hostIp: decoded['hostIp'] as String? ?? '',
      port: (decoded['port'] as num?)?.toInt() ?? 9527,
      token: decoded['token'] as String? ?? '',
      expireAt: DateTime.tryParse(decoded['expireAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      hotspotOwner: HotspotOwner.parse(decoded['hotspotOwner'] as String?),
    );
  }
}

class HotspotSession {
  const HotspotSession({
    required this.invite,
    required this.files,
    required this.createdAt,
    required this.nativeHotspotActive,
    required this.platformMessage,
  });

  final HotspotInvite invite;
  final List<TransferFile> files;
  final DateTime createdAt;
  final bool nativeHotspotActive;
  final String platformMessage;

  bool get isExpired => invite.isExpired;

  HotspotSession copyWith({
    HotspotInvite? invite,
    List<TransferFile>? files,
    DateTime? createdAt,
    bool? nativeHotspotActive,
    String? platformMessage,
  }) {
    return HotspotSession(
      invite: invite ?? this.invite,
      files: files ?? this.files,
      createdAt: createdAt ?? this.createdAt,
      nativeHotspotActive: nativeHotspotActive ?? this.nativeHotspotActive,
      platformMessage: platformMessage ?? this.platformMessage,
    );
  }
}
