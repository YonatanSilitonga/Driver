import 'package:dio/dio.dart';
import 'api_client.dart';

class DriverService {
  /// Ambil semua data Home Screen: profil, kendaraan, ringkasan rute, tugas aktif
  static Future<Map<String, dynamic>> getDashboard() async {
    try {
      final response = await ApiClient.dio.get('/driver/dashboard');

      if (response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      throw 'Gagal mengambil data dashboard';
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  static String _handleError(DioException e) {
    if (e.response?.statusCode == 401) {
      return 'Sesi berakhir. Silahkan login ulang.';
    }
    if (e.response?.data?['message'] != null) {
      return e.response!.data['message'] as String;
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return 'Tidak dapat terhubung ke server.';
    }
    return 'Terjadi kesalahan. Silahkan coba lagi.';
  }
}
