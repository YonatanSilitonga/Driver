import 'package:dio/dio.dart';
import '../utils/device_helper.dart';
import '../utils/network_exception.dart';
import 'api_client.dart';
import 'background_tracking.dart';

class AuthService {
  /// Login dengan email & password
  /// Return: map user jika berhasil, null jika gagal
  static Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final deviceId = await DeviceHelper.getDeviceId();
      final response = await ApiClient.dio.post(
        '/auth/login',
        data: {
          'email': email,
          'password': password,
          'device_id': deviceId,
        },
      );

      final body = response.data;
      if (body is! Map) return null;
      if (body['success'] != true) return null;

      final data = body['data'];
      if (data is! Map) return null;

      final token = data['token'];
      if (token is String && token.isNotEmpty) {
        await ApiClient.saveToken(token);
      }

      final user = data['user'];
      if (user is Map) {
        return Map<String, dynamic>.from(user);
      }
      return null;
    } on DioException catch (e) {
      throw NetworkException.from(e);
    } catch (e) {
      throw NetworkException.from(e);
    }
  }

  /// Logout: hapus token dari server dan dari HP
  static Future<void> logout() async {
    try {
      await sendOfflineSignal();
      await stopBackgroundTracking();
      await ApiClient.dio.post('/auth/logout');
    } catch (_) {
      // Abaikan error jaringan saat logout
    } finally {
      await ApiClient.clearDriverConfig();
      await ApiClient.clearToken();
    }
  }

  /// Ambil data user yang sedang login
  static Future<Map<String, dynamic>?> me() async {
    try {
      final response = await ApiClient.dio.get('/auth/me');
      final body = response.data;
      if (body is Map && body['success'] == true) {
        final data = body['data'];
        if (data is Map) return Map<String, dynamic>.from(data);
      }
      return null;
    } on DioException catch (e) {
      throw NetworkException.from(e);
    } catch (e) {
      throw NetworkException.from(e);
    }
  }
}