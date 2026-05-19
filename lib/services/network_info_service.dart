import 'dart:io';

class NetworkInfoService {
  Future<String> getLocalIp() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final value = address.address;
        if (!value.startsWith('169.254.') && value != '0.0.0.0') {
          return value;
        }
      }
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
