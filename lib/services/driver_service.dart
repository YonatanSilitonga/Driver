import 'package:dio/dio.dart';
import 'api_client.dart';

class DriverService {
  /// Ambil semua data Home Screen: profil, kendaraan, ringkasan rute, tugas aktif
  static Future<Map<String, dynamic>> getDashboard() async {
    try {
      final response = await ApiClient.dio.get('/driver/dashboard');

      final body = response.data;
      if (body is Map && body['success'] == true) {
        final data = body['data'];
        if (data is Map<String, dynamic>) return data;
        if (data is Map) return Map<String, dynamic>.from(data);
      }
      throw 'Gagal mengambil data dashboard';
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
