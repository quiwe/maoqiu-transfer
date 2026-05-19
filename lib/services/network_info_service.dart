import 'dart:io';

class NetworkInfoService {
  Future<String> getLocalIp() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    final candidates = <_IpCandidate>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final value = address.address;
        if (_isUsableIpv4(value)) {
          candidates.add(
            _IpCandidate(
              address: value,
              score: _interfaceScore(interface.name) + _addressScore(value),
            ),
          );
        }
      }
    }

    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => b.score.compareTo(a.score));
      return candidates.first.address;
    }

    return '0.0.0.0';
  }

  Future<String> getDeviceName() async {
    final hostname = Platform.localHostname.trim();
    if (hostname.isNotEmpty) {
      return hostname;
    }
    if (Platform.isAndroid) {
      return 'Android Phone';
    }
    if (Platform.isIOS) {
      return 'iPhone';
    }
    if (Platform.isWindows) {
      return 'Windows PC';
    }
    if (Platform.isMacOS) {
      return 'Mac';
    }
    if (Platform.isLinux) {
      return 'Linux PC';
    }
    return 'Unknown Device';
  }

  String getDeviceType() {
    if (Platform.isAndroid || Platform.isIOS) {
      return 'mobile';
    }
    return 'desktop';
  }
}

class _IpCandidate {
  const _IpCandidate({
    required this.address,
    required this.score,
  });

  final String address;
  final int score;
}

bool _isUsableIpv4(String value) {
  return value != '0.0.0.0' && !value.startsWith('169.254.');
}

int _addressScore(String value) {
  if (value.startsWith('192.168.')) {
    return 50;
  }
  if (value.startsWith('10.')) {
    return 45;
  }
  final parts = value.split('.');
  if (parts.length == 4) {
    final second = int.tryParse(parts[1]);
    if (parts[0] == '172' && second != null && second >= 16 && second <= 31) {
      return 45;
    }
  }
  return 0;
}

int _interfaceScore(String name) {
  final normalized = name.toLowerCase();
  const preferred = [
    'wi-fi',
    'wifi',
    'wlan',
    'ethernet',
    'en0',
    'en1',
    'eth',
  ];
  const virtual = [
    'virtual',
    'vethernet',
    'vmware',
    'virtualbox',
    'docker',
    'tailscale',
    'zerotier',
    'bluetooth',
    'loopback',
  ];

  if (virtual.any((item) => normalized.contains(item))) {
    return -100;
  }
  if (preferred.any((item) => normalized.contains(item))) {
    return 30;
  }
  return 0;
}
