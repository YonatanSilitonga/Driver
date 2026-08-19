import 'package:dio/dio.dart';
import 'api_client.dart';
import 'background_tracking.dart';

class AuthService {
  /// Login dengan email & password
  /// Return: map user jika berhasil, null jika gagal
 static Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final response = await ApiClient.dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );

      // ignore: avoid_print
      print('[LOGIN RAW] ${response.data}');

      final body = response.data;
      if (body is! Map) {
        return null;
      }
      if (body['success'] != true) {
        return null;
      }

      final data = body['data'];
      if (data is! Map) {
        return null;
      }

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
      // ignore: avoid_print
      print('❌ [LOGIN ERROR] baseUrl aktif: ${ApiClient.dio.options.baseUrl}');
      // ignore: avoid_print
      print('❌ [LOGIN ERROR] type: ${e.type}');
      // ignore: avoid_print
      print('❌ [LOGIN ERROR] statusCode: ${e.response?.statusCode}');
      // ignore: avoid_print
      print('❌ [LOGIN ERROR] data runtimeType: ${e.response?.data.runtimeType}');
      // ignore: avoid_print
      print('❌ [LOGIN ERROR] data: ${e.response?.data}');
      throw _handleError(e);
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
      throw _handleError(e);
    }
  }

static String _handleError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Koneksi ke server timeout. Periksa jaringan Anda.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Tidak dapat terhubung ke server. Pastikan backend berjalan.';
    }
    return 'Terjadi kesalahan. Silahkan coba lagi.';
}
}