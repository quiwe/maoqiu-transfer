import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdService {
  static const _deviceIdKey = 'device_id';
  static const _uuid = Uuid();

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final created = _uuid.v4();
    await prefs.setString(_deviceIdKey, created);
    return created;
  }
}
