// ignore_for_file: avoid_print

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static const String _defaultUrl = 'http://127.0.0.1:8081/api/v1';
  static const String _fallbackUrl = 'http://192.168.20.244:8081/api/v1';
  static const String _tokenKey = 'auth_token';

  static Dio? _dio;
  static String _activeBaseUrl = _defaultUrl;

  static Dio get dio {
    _dio ??= _createDio();
    return _dio!;
  }

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: _activeBaseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
      ),
    );

    // Interceptor: otomatis tambah token & fallback IP jika ADB Reverse terputus
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (DioException e, handler) async {
          if ((e.type == DioExceptionType.connectionTimeout ||
                  e.type == DioExceptionType.connectionError) &&
              _activeBaseUrl == _defaultUrl) {
            // Coba fallback otomatis ke IP Wi-Fi laptop (192.168.20.244)
            _activeBaseUrl = _fallbackUrl;
            _dio = null;
            try {
              final opts = e.requestOptions;
              final response = await ApiClient.dio.request(
                opts.path,
                data: opts.data,
                queryParameters: opts.queryParameters,
                options: Options(
                  method: opts.method,
                  headers: opts.headers,
                ),
              );
              return handler.resolve(response);
            } catch (_) {}
          }
          handler.next(e);
        },
      ),
    );

    return dio;
  }

  // Simpan token ke penyimpanan lokal HP
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  // Ambil token dari penyimpanan lokal HP
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  // Hapus token (logout)
  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    _dio = null; // reset dio instance
  }

  // Cek apakah sudah login
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // Kirim data GPS tracking driver ke server
  static Future<void> sendTrackingData({
    required double latitude,
    required double longitude,
    required int speed,
    required String status,
    int koli = 0,
  }) async {
    try {
      print('📡 [GPS TRACKING] Mengirim: ($latitude, $longitude) | Status: $status | Koli: $koli');
      final res = await dio.post(
        '/driver/tracking',
        data: {
          'id_ritase': 0,    // 0 menandakan belum ada ritase (disimpan sebagai NULL di Supabase)
          'id_kendaraan': 2, // Kendaraan B 9806 UXV
          'id_driver': 3,    // Driver AWALUDIN
          'latitude': latitude,
          'longitude': longitude,
          'kecepatan': speed,
          'arah': 0,
          'status': status,
          'jumlah_koli': koli,
        },
      );
      print('✅ [GPS TRACKING] Berhasil tersimpan di database Supabase: ${res.data}');
    } catch (e) {
      print('❌ [GPS TRACKING] Gagal mengirim: $e');
    }
  }
}
