// ignore_for_file: avoid_print

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/network_exception.dart';

class ApiClient {
  static const String _defaultUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.86.178.182:8080/api/v1',
  );
  // Fallback: ADB Reverse (USB cable)
  static const String _fallbackUrl = String.fromEnvironment(
    'API_URL_FALLBACK',
    defaultValue: 'http://127.0.0.1:8080/api/v1',
  );
  static const String _tokenKey = 'auth_token';

  static Dio? _dio;
  static String _activeBaseUrl = _defaultUrl;

  /// Base URL API yang sedang aktif (default/fallback yang berhasil dipakai).
  static String get baseUrl => _activeBaseUrl;

  /// Reset active base URL kembali ke default URL (127.0.0.1:8081 via ADB).
  static void resetToBaseUrl() {
    _activeBaseUrl = _defaultUrl;
    _dio = null;
  }

  static Dio get dio {
    _dio ??= _createDio();
    return _dio!;
  }

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: _activeBaseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning':
              'true', // Wajib untuk API via Ngrok Free
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
          final isNgrokOffline =
              e.response?.statusCode == 404 &&
              (e.response?.data?.toString().contains('ngrok') ?? false);
          if ((e.type == DioExceptionType.connectionTimeout ||
                  e.type == DioExceptionType.connectionError ||
                  isNgrokOffline) &&
              _activeBaseUrl == _defaultUrl &&
              _fallbackUrl != _defaultUrl) {
            // Coba fallback URL
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
            } catch (_) {
              // Jika fallback juga gagal, kembalikan ke default URL agar tidak tersangkut di IP mati
              _activeBaseUrl = _defaultUrl;
              _dio = null;
            }
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
  static const String _keyUserRole = 'config_user_role';
  static const String _keySellerId = 'config_seller_id';

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

  // Ambil konfigurasi identitas tracking (identitas murni dari hasil login —
  // tidak ada default AWALUDIN lagi; 0 = belum terisi).
  static Future<Map<String, dynamic>> loadDriverConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'id_driver': prefs.getInt(_keyIdDriver) ?? 0,
      'id_kendaraan': prefs.getInt(_keyIdKendaraan) ?? 0,
      'id_ritase': prefs.getInt(_keyIdRitase) ?? 0,
      'driver_name': prefs.getString(_keyDriverName) ?? '',
    };
  }

  // Hapus konfigurasi identitas (dipanggil saat logout biar login berikutnya bersih).
  static Future<void> clearDriverConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIdDriver);
    await prefs.remove(_keyIdKendaraan);
    await prefs.remove(_keyIdRitase);
    await prefs.remove(_keyDriverName);
    await prefs.remove(_keyUserRole);
    await prefs.remove(_keySellerId);
  }

  // ── Konfigurasi role user (driver/kapten) ──
  static Future<void> saveUserRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserRole, role);
  }

  static Future<String> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserRole) ?? 'driver';
  }

  static Future<void> saveSellerId(int sellerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySellerId, sellerId);
  }

  static Future<int> getSellerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keySellerId) ?? 0;
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

  /// Helper POST auth — lempar NetworkException biar pesan ramah pengguna.
  static Future<void> _postAuth(String path, Map<String, dynamic> data) async {
    try {
      await dio.post(path, data: data);
    } on DioException catch (e) {
      throw NetworkException.from(e);
    } catch (e) {
      throw NetworkException.from(e);
    }
  }

  /// Lupa password (tanpa OTP) — verifikasi username + no_hp driver.
  static Future<void> resetPassword({
    required String username,
    required String noHp,
    required String newPassword,
  }) async {
    await _postAuth('/auth/reset-password', {
      'username': username,
      'no_hp': noHp,
      'new_password': newPassword,
    });
  }

  /// Ganti password (user yang sedang login).
  static Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _postAuth('/auth/change-password', {
      'old_password': oldPassword,
      'new_password': newPassword,
    });
  }

  // Kirim data GPS tracking driver ke server (UPSERT: 1 posisi live per kendaraan)
  static Future<void> sendTrackingData({
    required double latitude,
    required double longitude,
    required int speed,
    required String status,
    int koli = 0,
    int ecer = 0,
    int highValue = 0,
    int durasiDetik = 0,
    int idDriver = 0,
    int idKendaraan = 0,
    int idRitase = 0,
    String? namaLokasi,
  }) async {
    // Identitas belum terisi (belum login / config kosong) → jangan kirim data palsu.
    if (idKendaraan <= 0) {
      print(
        '⚠️ [GPS TRACKING] Skip — id_kendaraan belum terisi (belum login).',
      );
      return;
    }
    try {
      print(
        '📡 [GPS TRACKING] Mengirim: ($latitude, $longitude) | Status: $status | Koli: $koli | Ecer: $ecer | HV: $highValue | Durasi: $durasiDetik dtk',
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
          'jumlah_high_value': highValue,
          'durasi_detik': durasiDetik,
          'nama_lokasi': namaLokasi,
        },
      );
      print(
        '✅ [GPS TRACKING] Berhasil tersimpan di database Supabase: ${res.data}',
      );
    } catch (e) {
      // Jaringan goyang → retry sekali setelah 15 detik (ambang offline backend = 3 mnt).
      print('❌ [GPS TRACKING] Gagal kirim, retry 15s: $e');
      await Future.delayed(const Duration(seconds: 15));
      try {
        await dio.post(
          '/driver/tracking',
          data: {
            'id_ritase': idRitase,
            'id_kendaraan': idKendaraan,
            'id_driver': idDriver,
            'latitude': latitude,
            'longitude': longitude,
            'kecepatan': speed,
            'arah': 0,
            'status': status,
            'jumlah_koli': koli,
            'jumlah_ecer': ecer,
            'jumlah_high_value': highValue,
            'durasi_detik': durasiDetik,
          },
        );
        print('✅ [GPS TRACKING] Berhasil setelah retry.');
      } catch (e2) {
        print('❌ [GPS TRACKING] Gagal juga setelah retry: $e2');
      }
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
    int highValue = 0,
    int durasiDetik = 0,
    String? namaLokasi,
    String? fotoManifestUrl,
  }) async {
    final payload = {
      'id_ritase': idRitase,
      'status': status,
      'nama_lokasi': namaLokasi ?? '',
      'latitude': latitude,
      'longitude': longitude,
      'jumlah_koli': koli,
      'jumlah_ecer': ecer,
      'jumlah_high_value': highValue,
      'durasi_detik': durasiDetik,
      'foto_manifest_url': fotoManifestUrl ?? '',
    };
    try {
      print(
        '📤 [STATUS] Update ritase=$idRitase -> $status | Loc: $namaLokasi | Koli: $koli | Ecer: $ecer | HV: $highValue | Foto: $fotoManifestUrl ($durasiDetik dtk)',
      );
      final res = await dio.post('/driver/trip-status', data: payload);
      print('✅ [STATUS] Tersimpan: ${res.data}');
    } catch (e) {
      print('❌ [STATUS] Gagal mengirim, retry 2s: $e');
      await Future.delayed(const Duration(seconds: 2));
      try {
        final res = await dio.post('/driver/trip-status', data: payload);
        print('✅ [STATUS] Tersimpan setelah retry: ${res.data}');
      } catch (e2) {
        print('❌ [STATUS] Gagal mengirim setelah retry: $e2');
      }
    }
  }

  // Upload foto bukti manifest dari driver
  static Future<String?> uploadManifestPhoto({
    required int idRitase,
    required String filePath,
    String? namaLokasi,
    int? idStop,
  }) async {
    try {
      print('📤 [UPLOAD MANIFEST] Mengunggah foto: $filePath...');
      final formData = FormData.fromMap({
        'id_ritase': idRitase,
        'nama_lokasi': namaLokasi ?? '',
        'id_stop': idStop ?? 0,
        'file': await MultipartFile.fromFile(
          filePath,
          filename: 'manifest.webp',
        ),
      });
      final res = await dio.post('/driver/upload-manifest', data: formData);
      print('✅ [UPLOAD MANIFEST] Berhasil: ${res.data}');
      if (res.statusCode == 200 &&
          res.data != null &&
          res.data['data'] != null) {
        return res.data['data']['photo_url']?.toString();
      }
      return null;
    } catch (e) {
      print('❌ [UPLOAD MANIFEST] Gagal: $e');
      return null;
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

  /// Ambil riwayat ritase selesai milik driver
  static Future<List<Map<String, dynamic>>> fetchDriverHistory({
    int? idDriver,
    String filter = 'all',
    String? startDate,
    String? endDate,
  }) async {
    try {
      var driverId = idDriver ?? 0;
      if (driverId == 0) {
        final cfg = await loadDriverConfig();
        driverId = cfg['id_driver'] ?? 0;
      }
      final queryParams = <String, dynamic>{
        'id_driver': driverId,
        'filter': filter,
      };
      if (startDate != null && startDate.isNotEmpty) {
        queryParams['start_date'] = startDate;
      }
      if (endDate != null && endDate.isNotEmpty) {
        queryParams['end_date'] = endDate;
      }
      final res = await dio.get(
        '/driver/history-ritase',
        queryParameters: queryParams,
      );
      if (res.statusCode == 200 && res.data != null) {
        final body = res.data;
        if (body is Map && body['data'] is List) {
          return List<Map<String, dynamic>>.from(body['data']);
        } else if (body is List) {
          return List<Map<String, dynamic>>.from(body);
        }
      }
      return [];
    } on DioException catch (e) {
      throw NetworkException.from(e);
    } catch (e) {
      throw NetworkException.from(e);
    }
  }

  /// Ambil detail stop & manifest ritase riwayat
  static Future<Map<String, dynamic>?> fetchDriverHistoryDetail(
    int idRitase,
  ) async {
    try {
      final res = await dio.get('/driver/history-ritase/$idRitase');
      if (res.statusCode == 200 && res.data != null) {
        final body = res.data;
        if (body is Map && body['data'] != null) {
          return Map<String, dynamic>.from(body['data']);
        }
      }
    } catch (e) {
      print('❌ [FETCH HISTORY DETAIL] Gagal: $e');
    }
    return null;
  }

  /// Cek versi aplikasi terbaru dari API server (tanpa cache)
  static Future<Map<String, dynamic>?> checkAppVersion() async {
    try {
      final res = await dio.get(
        '/app/version',
        queryParameters: {'_t': DateTime.now().millisecondsSinceEpoch},
      );
      if (res.statusCode == 200 && res.data != null) {
        return Map<String, dynamic>.from(res.data);
      }
    } catch (e) {
      print('❌ [API] Gagal checkAppVersion: $e');
    }
    return null;
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
  static Future<Map<String, dynamic>?> fetchActiveRitase(
    int idDriver,
    int idKendaraan,
  ) async {
    try {
      final response = await dio.get(
        '/driver/active-ritase',
        queryParameters: {'id_driver': idDriver, 'id_kendaraan': idKendaraan},
      );

      final body = response.data;
      if (body is Map && body['success'] == true) {
        final data = body['data'];
        if (data is Map<String, dynamic>) return data;
        if (data is Map) return Map<String, dynamic>.from(data);
      }
      return null;
    } on DioException catch (e) {
      throw NetworkException.from(e);
    } catch (e) {
      throw NetworkException.from(e);
    }
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
  static Future<Map<String, dynamic>?> startFreeTrip(
    int idDriver,
    int idKendaraan,
  ) async {
    try {
      final response = await dio.post(
        '/driver/start-free-trip',
        data: {'id_driver': idDriver, 'id_kendaraan': idKendaraan},
      );
      if (response.data != null && response.data['success'] == true) {
        return response.data['data'];
      }
    } catch (e) {
      print('❌ [API] Gagal startFreeTrip: $e');
    }
    return null;
  }

  // Tambahkan stop/lokasi baru ke perjalanan aktif
  static Future<Map<String, dynamic>?> addStop(
    int idRitase,
    int idSeller,
  ) async {
    try {
      final response = await dio.post(
        '/driver/add-stop',
        data: {'id_ritase': idRitase, 'id_seller': idSeller},
      );
      if (response.data != null && response.data['success'] == true) {
        return response.data['data'];
      }
    } catch (e) {
      print('❌ [API] Gagal addStop: $e');
    }
    return null;
  }

  // ── KAPTEN ENDPOINTS ──

  /// Ambil info seller kapten yang sedang login
  static Future<Map<String, dynamic>?> fetchKaptenSellerInfo() async {
    try {
      final res = await dio.get('/kapten/seller-info');
      if (res.statusCode == 200 && res.data != null) {
        final body = res.data;
        if (body is Map && body['data'] != null) {
          return Map<String, dynamic>.from(body['data']);
        }
      }
    } catch (e) {
      print('❌ [KAPTEN] Gagal fetchSellerInfo: $e');
    }
    return null;
  }

  /// Ambil data cargo hari ini untuk lokasi kapten (pre-fill form)
  static Future<Map<String, dynamic>?> fetchTodayCargo({int? idRitase, String? jenisRitase, int? ritaseKe}) async {
    try {
      final params = <String>[];
      if (idRitase != null && idRitase > 0) params.add('id_ritase=$idRitase');
      if (jenisRitase != null && jenisRitase.isNotEmpty) params.add('jenis_ritase=$jenisRitase');
      if (ritaseKe != null && ritaseKe > 0) params.add('ritase_ke=$ritaseKe');
      final query = params.isNotEmpty ? '?${params.join('&')}' : '';
      final res = await dio.get('/kapten/today-cargo$query');
      if (res.statusCode == 200 && res.data != null) {
        final body = res.data;
        if (body is Map && body['data'] != null) {
          return Map<String, dynamic>.from(body['data']);
        }
      }
    } catch (e) {
      print('❌ [KAPTEN] Gagal fetchTodayCargo: $e');
    }
    return null;
  }

  /// Ambil daftar ritase yang singgah di seller kapten hari ini
  static Future<List<Map<String, dynamic>>> fetchKaptenRitase() async {
    try {
      final res = await dio.get('/kapten/my-seller-ritase');
      if (res.statusCode == 200 && res.data != null) {
        final body = res.data;
        if (body is Map && body['data'] is List) {
          return List<Map<String, dynamic>>.from(body['data']);
        } else if (body is List) {
          return List<Map<String, dynamic>>.from(body);
        }
      }
      return [];
    } on DioException catch (e) {
      throw NetworkException.from(e);
    } catch (e) {
      throw NetworkException.from(e);
    }
  }

  /// Kapten input data muatan (12 field + foto)
  static Future<Map<String, dynamic>?> submitKaptenCargo({
    required int idRitase,
    required int idStop,
    required String jenisRitase,
    required int ritaseKe,
    required int jumlahAwb,
    required int koliJkt, required int koliSeg, required int koliBtn,
    required int ecerJkt, required int ecerSeg, required int ecerBtn,
    required int koliHvJkt, required int koliHvSeg, required int koliHvBtn,
    required int ecerHvJkt, required int ecerHvSeg, required int ecerHvBtn,
    String? namaLokasi,
    double? latitude,
    double? longitude,
    String? fotoManifestUrl,
    String? catatan,
  }) async {
    try {
      final res = await dio.post('/kapten/cargo-input', data: {
        'id_ritase': idRitase,
        'id_stop': idStop,
        'jenis_ritase': jenisRitase,
        'ritase_ke': ritaseKe,
        'nama_lokasi': namaLokasi ?? '',
        'latitude': latitude ?? 0,
        'longitude': longitude ?? 0,
        'jumlah_awb': jumlahAwb,
        'koli_jkt': koliJkt, 'koli_seg': koliSeg, 'koli_btn': koliBtn,
        'ecer_jkt': ecerJkt, 'ecer_seg': ecerSeg, 'ecer_btn': ecerBtn,
        'koli_hv_jkt': koliHvJkt, 'koli_hv_seg': koliHvSeg, 'koli_hv_btn': koliHvBtn,
        'ecer_hv_jkt': ecerHvJkt, 'ecer_hv_seg': ecerHvSeg, 'ecer_hv_btn': ecerHvBtn,
        'foto_manifest_url': fotoManifestUrl ?? '',
        'catatan': catatan ?? '',
      });
      if (res.statusCode == 201 && res.data != null) {
        final body = res.data;
        if (body is Map && body['data'] != null) {
          return Map<String, dynamic>.from(body['data']);
        }
      }
      return null;
    } on DioException catch (e) {
      throw NetworkException.from(e);
    } catch (e) {
      throw NetworkException.from(e);
    }
  }

  // ── KAPTEN MULTI-SELLER ──

  /// Ambil daftar seller yang bisa diakses kapten
  static Future<List<Map<String, dynamic>>> getMySellers() async {
    try {
      final res = await dio.get('/kapten/my-sellers');
      if (res.statusCode == 200 && res.data != null) {
        final body = res.data;
        if (body is Map && body['data'] is Map) {
          final data = body['data'];
          if (data['sellers'] is List) {
            return List<Map<String, dynamic>>.from(data['sellers']);
          }
        }
      }
      return [];
    } on DioException catch (e) {
      throw NetworkException.from(e);
    } catch (e) {
      throw NetworkException.from(e);
    }
  }

  /// Pilih seller → return token baru dengan seller_id yang dipilih
  static Future<Map<String, dynamic>?> selectSeller(int sellerId) async {
    try {
      final res = await dio.post('/kapten/select-seller', data: {
        'seller_id': sellerId,
      });
      if (res.statusCode == 200 && res.data != null) {
        final body = res.data;
        if (body is Map && body['data'] != null) {
          return Map<String, dynamic>.from(body['data']);
        }
      }
      return null;
    } on DioException catch (e) {
      throw NetworkException.from(e);
    } catch (e) {
      throw NetworkException.from(e);
    }
  }

  // ── KAPTEN KONFIRMASI PENGAMBILAN ──

  /// Ambil grup input hari ini yang belum ter-link ke ritase (bahan konfirmasi)
  static Future<List<Map<String, dynamic>>> fetchPendingConfirmations() async {
    try {
      final res = await dio.get('/kapten/pending-confirmations');
      if (res.statusCode == 200 && res.data != null) {
        final body = res.data;
        if (body is Map && body['data'] is List) {
          return List<Map<String, dynamic>>.from(body['data']);
        }
      }
      return [];
    } on DioException catch (e) {
      throw NetworkException.from(e);
    } catch (e) {
      throw NetworkException.from(e);
    }
  }

  /// Konfirmasi driver pengambil: tautkan semua input NULL dalam grup
  /// (jenis_ritase + ritase_ke) hari ini ke ritase pilihan kapten SEKALIGUS
  /// mencatat realisasi pengambilan (diambil_*, foto, catatan).
  /// Return {'id_ritase': ..., 'total_linked': ..., 'id_konfirmasi': ..., 'sisa': {...}}.
  static Future<Map<String, dynamic>?> confirmPickup({
    required String jenisRitase,
    required int ritaseKe,
    required int idRitase,
    int jumlahAwb = 0,
    int koliJkt = 0, int koliSeg = 0, int koliBtn = 0,
    int ecerJkt = 0, int ecerSeg = 0, int ecerBtn = 0,
    int koliHvJkt = 0, int koliHvSeg = 0, int koliHvBtn = 0,
    int ecerHvJkt = 0, int ecerHvSeg = 0, int ecerHvBtn = 0,
    String? fotoPenjemputanUrl,
    String? catatan,
  }) async {
    try {
      final res = await dio.post('/kapten/confirm-pickup', data: {
        'jenis_ritase': jenisRitase,
        'ritase_ke': ritaseKe,
        'id_ritase': idRitase,
        'diambil_awb': jumlahAwb,
        'diambil_koli_jkt': koliJkt, 'diambil_koli_seg': koliSeg, 'diambil_koli_btn': koliBtn,
        'diambil_ecer_jkt': ecerJkt, 'diambil_ecer_seg': ecerSeg, 'diambil_ecer_btn': ecerBtn,
        'diambil_koli_hv_jkt': koliHvJkt, 'diambil_koli_hv_seg': koliHvSeg, 'diambil_koli_hv_btn': koliHvBtn,
        'diambil_ecer_hv_jkt': ecerHvJkt, 'diambil_ecer_hv_seg': ecerHvSeg, 'diambil_ecer_hv_btn': ecerHvBtn,
        'foto_penjemputan_url': fotoPenjemputanUrl ?? '',
        'catatan': catatan ?? '',
      });
      if (res.statusCode == 200 && res.data != null) {
        final body = res.data;
        if (body is Map && body['data'] != null) {
          return Map<String, dynamic>.from(body['data']);
        }
      }
      return null;
    } on DioException catch (e) {
      throw NetworkException.from(e);
    } catch (e) {
      throw NetworkException.from(e);
    }
  }

  /// Riwayat serah terima hari ini + sisa per grup.
  /// Return {'riwayat': [...], 'sisa_grup': [...]}.
  static Future<Map<String, dynamic>?> fetchKonfirmasiPenjemputan() async {
    try {
      final res = await dio.get('/kapten/konfirmasi-penjemputan');
      if (res.statusCode == 200 && res.data != null) {
        final body = res.data;
        if (body is Map && body['data'] is Map) {
          return Map<String, dynamic>.from(body['data']);
        }
      }
      return null;
    } on DioException catch (e) {
      throw NetworkException.from(e);
    } catch (e) {
      throw NetworkException.from(e);
    }
  }
}
