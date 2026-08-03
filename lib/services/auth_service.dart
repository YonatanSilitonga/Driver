import 'package:dio/dio.dart';
import 'api_client.dart';

class AuthService {
  /// Login dengan email & password
  /// Return: token string jika berhasil, null jika gagal
  static Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final response = await ApiClient.dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );

      if (response.data['success'] == true) {
        final token = response.data['data']['token'] as String;
        final user = response.data['data']['user'];
        await ApiClient.saveToken(token);
        return user;
      }
      return null;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Logout: hapus token dari server dan dari HP
  static Future<void> logout() async {
    try {
      await ApiClient.dio.post('/auth/logout');
    } catch (_) {
      // Abaikan error jaringan saat logout
    } finally {
      await ApiClient.clearToken();
    }
  }

  /// Ambil data user yang sedang login
  static Future<Map<String, dynamic>?> me() async {
    try {
      final response = await ApiClient.dio.get('/auth/me');
      if (response.data['success'] == true) {
        return response.data['data'];
      }
      return null;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  static String _handleError(DioException e) {
    if (e.response?.data?['message'] != null) {
      return e.response!.data['message'] as String;
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
