// ignore_for_file: avoid_print

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  // Default → backend ngrok kawan (office). Override via:
  //   flutter run --dart-define=API_URL=<url>/api/v1
  static const String _defaultUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://violator-krypton-image.ngrok-free.dev/api/v1',
  );
  static const String _fallbackUrl = String.fromEnvironment(
    'API_URL_FALLBACK',
    defaultValue: 'https://violator-krypton-image.ngrok-free.dev/api/v1',
  );
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
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true', // Wajib untuk API via Ngrok Free
        },
      ),
    );

    // Interceptor: otomatis tambah token & fallback otomatis ngrok -> LAN
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
            // ngrok tidak terjangkau -> coba LAN laptop sekali
            _activeBaseUrl = _fallbackUrl;
            _dio = null;
            try {
              final opts = e.requestOptions;
              final response = await ApiClient.dio.request(
                opts.path,
                data: opts.data,
                queryParameters: opts.queryParameters,
                options: Options(method: opts.method, headers: opts.headers),
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

  // ── Konfigurasi identitas driver / kendaraan / ritase ──
  static const String _keyIdDriver = 'config_id_driver';
  static const String _keyIdKendaraan = 'config_id_kendaraan';
  static const String _keyIdRitase = 'config_id_ritase';
  static const String _keyDriverName = 'config_driver_name';

  // Simpan konfigurasi identitas tracking (dipakai di halaman pengaturan)
  static Future<void> saveDriverConfig({
    required int idDriver,
    required int idKendaraan,
    required int idRitase,
    String? driverName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyIdDriver, idDriver);
    await prefs.setInt(_keyIdKendaraan, idKendaraan);
    await prefs.setInt(_keyIdRitase, idRitase);
    if (driverName != null && driverName.isNotEmpty) {
      await prefs.setString(_keyDriverName, driverName);
    }
  }

  // Ambil konfigurasi identitas tracking (default: akun uji AWALUDIN)
  static Future<Map<String, dynamic>> loadDriverConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'id_driver': prefs.getInt(_keyIdDriver) ?? 3,
      'id_kendaraan': prefs.getInt(_keyIdKendaraan) ?? 2,
      'id_ritase': prefs.getInt(_keyIdRitase) ?? 4,
      'driver_name': prefs.getString(_keyDriverName) ?? 'AWALUDIN',
    };
  }

  /// Catat kapan app dibuka (telemetry backend). Fire-and-forget, aman dipanggil
  /// saat home kebuka / resume dari background.
  static Future<void> markAppOpen() async {
    try {
      await dio.post('/driver/open');
    } catch (e) {
      print('[APP OPEN] gagal mencatat: $e');
    }
  }

  // Kirim data GPS tracking driver ke server (UPSERT: 1 posisi live per kendaraan)
  static Future<void> sendTrackingData({
    required double latitude,
    required double longitude,
    required int speed,
    required String status,
    int koli = 0,
    int ecer = 0,
    int durasiDetik = 0,
    int idDriver = 3,
    int idKendaraan = 2,
    int idRitase = 0,
  }) async {
    try {
      print(
        '📡 [GPS TRACKING] Mengirim: ($latitude, $longitude) | Status: $status | Koli: $koli | Ecer: $ecer | Durasi: $durasiDetik dtk',
      );
      final res = await dio.post(
        '/driver/tracking',
        data: {
          'id_ritase':
              idRitase, // 0 menandakan belum ada ritase (disimpan sebagai NULL di Supabase)
          'id_kendaraan': idKendaraan,
          'id_driver': idDriver,
          'latitude': latitude,
          'longitude': longitude,
          'kecepatan': speed,
          'arah': 0,
          'status': status,
          'jumlah_koli': koli,
          'jumlah_ecer': ecer,
          'durasi_detik': durasiDetik,
        },
      );
      print(
        '✅ [GPS TRACKING] Berhasil tersimpan di database Supabase: ${res.data}',
      );
    } catch (e) {
      print('❌ [GPS TRACKING] Gagal mengirim: $e');
    }
  }

  // Kirim update status manual driver -> simpan riwayat (ritase_event) + durasi stage
  static Future<void> sendStatusUpdate({
    required int idRitase,
    required String status,
    required double latitude,
    required double longitude,
    int koli = 0,
    int ecer = 0,
    int durasiDetik = 0,
  }) async {
    final targetId = idRitase > 0 ? idRitase : 4;
    try {
      print('📤 [STATUS] Update $targetId -> $status | Koli: $koli | Ecer: $ecer ($durasiDetik dtk)');
      final res = await dio.post(
        '/armada/ritase/$targetId/status',
        data: {
          'status': status,
          'latitude': latitude,
          'longitude': longitude,
          'jumlah_koli': koli,
          'jumlah_ecer': ecer,
          'durasi_detik': durasiDetik,
        },
      );
      print('✅ [STATUS] Tersimpan: ${res.data}');
    } catch (e) {
      print('❌ [STATUS] Gagal mengirim: $e');
    }
  }

  static Future<bool> finishRitase(int idRitase) async {
    try {
      final res = await dio.post(
        '/driver/finish-ritase',
        data: {'id_ritase': idRitase},
      );
      return res.statusCode == 200;
    } catch (e) {
      print('❌ [FINISH RITASE] Gagal: $e');
      return false;
    }
  }

  static Future<bool> resetDriverTestRitase(int idDriver) async {
    try {
      final res = await dio.post(
        '/driver/reset-test-ritase',
        data: {'id_driver': idDriver},
      );
      return res.statusCode == 200;
    } catch (e) {
      print('❌ [RESET TEST RITASE] Gagal: $e');
      return false;
    }
  }

  // Ambil daftar kendaraan dari API Backend
  static Future<List<dynamic>> fetchVehicles() async {
    try {
      final response = await dio.get('/vehicles');
      final body = response.data;
      if (body is Map && body['success'] == true) {
        final data = body['data'];
        if (data is List) return data;
      } else if (body is List) {
        return body;
      }
    } catch (e) {
      print('❌ [API] Gagal fetchVehicles: $e');
    }
    return [];
  }

  // Ambil ritase aktif berdasarkan driver dan kendaraan
  static Future<Map<String, dynamic>?> fetchActiveRitase(int idDriver, int idKendaraan) async {
    try {
      final response = await dio.get('/driver/active-ritase', queryParameters: {
        'id_driver': idDriver,
        'id_kendaraan': idKendaraan,
      });

      final body = response.data;
      if (body is Map && body['success'] == true) {
        final data = body['data'];
        if (data is Map<String, dynamic>) return data;
        if (data is Map) return Map<String, dynamic>.from(data);
      }
    } catch (e) {
      print('❌ [API] Gagal fetchActiveRitase: $e');
    }
    return null;
  }

  // Ambil daftar seller dari backend
  static Future<List<dynamic>> fetchSellers() async {
    try {
      final response = await dio.get('/sellers');
      if (response.data != null && response.data['success'] == true) {
        return response.data['data'] ?? [];
      } else if (response.data is List) {
        return response.data;
      }
    } catch (e) {
      print('❌ [API] Gagal fetchSellers: $e');
    }
    return [];
  }

  // Mulai perjalanan bebas
  static Future<Map<String, dynamic>?> startFreeTrip(int idDriver, int idKendaraan) async {
    try {
      final response = await dio.post('/driver/start-free-trip', data: {
        'id_driver': idDriver,
        'id_kendaraan': idKendaraan,
      });
      if (response.data != null && response.data['success'] == true) {
        return response.data['data'];
      }
    } catch (e) {
      print('❌ [API] Gagal startFreeTrip: $e');
    }
    return null;
  }

  // Tambahkan stop/lokasi baru ke perjalanan aktif
  static Future<Map<String, dynamic>?> addStop(int idRitase, int idSeller) async {
    try {
      final response = await dio.post('/driver/add-stop', data: {
        'id_ritase': idRitase,
        'id_seller': idSeller,
      });
      if (response.data != null && response.data['success'] == true) {
        return response.data['data'];
      }
    } catch (e) {
      print('❌ [API] Gagal addStop: $e');
    }
    return null;
  }
}
