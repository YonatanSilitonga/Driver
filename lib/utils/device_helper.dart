import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceHelper {
  static const String _deviceIdKey = 'app_unique_device_id';
  static String? _cachedDeviceId;

  /// Mengambil atau membuat Device ID unik untuk instalasi aplikasi ini.
  /// ID ini persisten selama aplikasi terpasang di HP, dan akan otomatis hilang jika aplikasi di-uninstall.
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null && _cachedDeviceId!.isNotEmpty) {
      return _cachedDeviceId!;
    }

    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);

    if (deviceId == null || deviceId.isEmpty) {
      final random = Random.secure();
      final values = List<int>.generate(8, (i) => random.nextInt(256));
      final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}_$hex';
      await prefs.setString(_deviceIdKey, deviceId);
    }

    _cachedDeviceId = deviceId;
    return deviceId;
  }
}
