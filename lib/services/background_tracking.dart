// ignore_for_file: avoid_print

import 'dart:async';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api_client.dart';

/// Background tracking (foreground service) — flutter_foreground_task v10.
/// Identitas driver/kendaraan/ritase diambil dari config yang sudah disimpan
/// oleh `ApiClient.saveDriverConfig` (login & saat trip mulai).
/// Integrasi:
///   - Login sukses → `startBackgroundTracking()`
///   - Logout → `stopBackgroundTracking()`
///   - Android 10+: izin "Izinkan semua waktu" diaktifkan manual di Settings.
///   - HP Xiaomi/OPPO/Vivo: exempt dari battery optimization biar gak di-kill.


/// Dio khusus background — pakai token dari penyimpanan (WAJIB, endpoint /driver/* JWT).
Future<Dio> _bgDio() async {
  final dio = Dio(BaseOptions(
    baseUrl: ApiClient.baseUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 25),
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
    },
  ));
  final token = await ApiClient.getToken();
  if (token != null && token.isNotEmpty) {
    dio.options.headers['Authorization'] = 'Bearer $token';
  }
  return dio;
}

/// Kirim satu request tracking — kalau gagal, retry sekali setelah 15 detik
/// (tahan jaringan goyang; ambang offline backend = 3 menit).
Future<void> _postWithRetry(Dio dio, Map<String, dynamic> data) async {
  Future<void> attempt() async {
    await dio.post('/driver/tracking', data: data);
  }

  try {
    await attempt();
  } catch (e) {
    print('[BG TRACKING] gagal, retry 15s: $e');
    await Future.delayed(const Duration(seconds: 15));
    await attempt();
  }
}

/// Kirim heartbeat / pergerakan posisi ke backend dari background (layar mati / di-background).
/// Hitung kecepatan dari delta posisi (GPS hardware speed sering 0 saat layar mati)
/// biar dashboard gak selalu "Berhenti".
Position? _lastBgPosition;
DateTime? _lastBgSentTime;
double? _prevBgLat;
double? _prevBgLng;
DateTime? _prevBgTime;

/// Kirim payload tracking ke backend
Future<void> _sendTrackingPayload({
  required Position pos,
  required bool isHeartbeat,
}) async {
  try {
    final cfg = await ApiClient.loadDriverConfig();
    var idDriver = cfg['id_driver'] as int? ?? 0;
    var idKendaraan = cfg['id_kendaraan'] as int? ?? 0;
    final role = (cfg['role'] ?? '').toString().trim().toLowerCase();
    final idUser = cfg['id_user'] as int? ?? 0;
    if (role == 'driver_pickup') {
      if (idDriver <= 0) idDriver = (idUser > 0 ? idUser : 39);
      if (idKendaraan <= 0) idKendaraan = 18;
    }
    if (idDriver <= 0 || idKendaraan <= 0) return; // identitas belum lengkap

    final token = await ApiClient.getToken();
    if (token == null || token.isEmpty) return; // belum login → jangan kirim

    final idRitase = cfg['id_ritase'] as int? ?? 0;
    final now = DateTime.now();

    // Hitung kecepatan: jika bukan heartbeat (bergerak), gunakan speed hardware atau delta
    int speedKmh = 0;
    if (!isHeartbeat) {
      var speedCalc = (pos.speed < 0 ? 0.0 : pos.speed * 3.6).round();
      if (speedCalc == 0 &&
          _prevBgLat != null &&
          _prevBgLng != null &&
          _prevBgTime != null) {
        final dtSec = now.difference(_prevBgTime!).inSeconds;
        if (dtSec > 0) {
          final distM = Geolocator.distanceBetween(
            _prevBgLat!,
            _prevBgLng!,
            pos.latitude,
            pos.longitude,
          );
          speedCalc = ((distM / dtSec) * 3.6).round();
        }
      }
      speedKmh = speedCalc;
    } else {
      // Saat diam / macet (Heartbeat), kecepatan 0 km/h
      speedKmh = 0;
    }

    _prevBgLat = pos.latitude;
    _prevBgLng = pos.longitude;
    _prevBgTime = now;
    _lastBgPosition = pos;
    _lastBgSentTime = now;

    final pickupStatus = (cfg['pickup_status'] ?? '').toString();
    String status = 'Background';
    if (role == 'driver_pickup') {
      if (pickupStatus == 'menuju_seller') {
        status = 'Sedang Menuju';
      } else if (pickupStatus == 'menuju_gudang') {
        status = 'Kembali ke Gudang';
      } else if (pickupStatus == 'selesai') {
        status = 'Selesai';
      } else {
        status = 'Standby';
      }
    }

    final dio = await _bgDio();
    await _postWithRetry(dio, {
      'id_driver': idDriver,
      'id_kendaraan': idKendaraan,
      'id_ritase': idRitase,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'kecepatan': speedKmh,
      'status': status,
      'durasi_detik': 0,
    });
    print('[BG TRACKING] Posisi terkirim: lat=${pos.latitude}, lng=${pos.longitude}, speed=$speedKmh (heartbeat=$isHeartbeat)');
  } catch (e) {
    print('[BG TRACKING] gagal kirim payload: $e');
  }
}

/// Sinyal "app/service berhenti" → backend langsung cap kendaraan OFFLINE.
/// Best-effort (onDestroy force-stop Android tidak selalu dipanggil).
/// Publik supaya bisa dipanggil eksplisit dari UI (misal konfirmasi keluar app).
Future<void> sendOfflineSignal() async {
  try {
    final cfg = await ApiClient.loadDriverConfig();
    var idDriver = cfg['id_driver'] as int? ?? 0;
    var idKendaraan = cfg['id_kendaraan'] as int? ?? 0;
    final role = (cfg['role'] ?? '').toString().trim().toLowerCase();
    final idUser = cfg['id_user'] as int? ?? 0;
    if (role == 'driver_pickup') {
      if (idDriver <= 0) idDriver = (idUser > 0 ? idUser : 39);
      if (idKendaraan <= 0) idKendaraan = 18;
    }
    if (idDriver <= 0 || idKendaraan <= 0) return;

    final token = await ApiClient.getToken();
    if (token == null || token.isEmpty) return;

    final dio = await _bgDio();
    await dio.post('/driver/tracking', data: {
      'id_driver': idDriver,
      'id_kendaraan': idKendaraan,
      'id_ritase': cfg['id_ritase'] ?? 0,
      'latitude': 0,
      'longitude': 0,
      'kecepatan': 0,
      'status': 'app_stopped',
      'offline': true,
    });
  } catch (e) {
    print('[BG TRACKING] sinyal offline gagal: $e');
  }
}

/// Handler yang dijalankan foreground service (isolate background).
class _BgTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _positionStreamSub;

  void _startPositionStream() {
    _positionStreamSub?.cancel();
    try {
      // Event-driven: GPS stream update saat kendaraan bergerak
      // Menggunakan distanceFilter 2m agar GPS hardware tetap responsif mengirim titik
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      );

      _positionStreamSub = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position pos) {
          final now = DateTime.now();
          final timeDiff = _lastBgSentTime == null ? 999 : now.difference(_lastBgSentTime!).inSeconds;

          double distMoved = 0.0;
          if (_lastBgPosition != null) {
            distMoved = Geolocator.distanceBetween(
              _lastBgPosition!.latitude,
              _lastBgPosition!.longitude,
              pos.latitude,
              pos.longitude,
            );
          } else {
            distMoved = 999.0;
          }

          // Aturan tracking: kirim jika interval >= 10 detik DAN pergerakan >= 5 meter
          if (timeDiff >= 10 && distMoved >= 5.0) {
            _sendTrackingPayload(pos: pos, isHeartbeat: false);
          }
        },
        onError: (err) {
          print('[BG TRACKING] Stream location error: $err');
        },
      );
      print('[BG TRACKING] getPositionStream aktif (10s interval / >= 5m filter)');
    } catch (e) {
      print('[BG TRACKING] Gagal start getPositionStream: $e');
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 1. Ambil & kirim lokasi awal (prioritaskan live satelit)
    try {
      Position? initialPos;
      try {
        initialPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 7),
          ),
        );
      } catch (_) {
        initialPos = await Geolocator.getLastKnownPosition();
      }
      if (initialPos != null) {
        await _sendTrackingPayload(pos: initialPos, isHeartbeat: false);
      }
    } catch (e) {
      print('[BG TRACKING] onStart get location gagal: $e');
    }

    // 2. Mulai stream pergerakan berjarak 30 meter
    _startPositionStream();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Pastikan stream tetap terhubung
    if (_positionStreamSub == null) {
      _startPositionStream();
    }

    // Heartbeat: Jika dalam 50 detik terakhir tidak ada pergerakan >= 10m (macet/parkir/loading),
    // kirim sinyal heartbeat dengan posisi terakhir agar backend tahu armada tetap online & diam.
    _checkHeartbeat();
  }

  Future<void> _checkHeartbeat() async {
    final now = DateTime.now();
    if (_lastBgSentTime == null || now.difference(_lastBgSentTime!).inSeconds >= 50) {
      Position? posToSend = _lastBgPosition;
      if (posToSend == null) {
        try {
          try {
            posToSend = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 5),
              ),
            );
          } catch (_) {
            posToSend = await Geolocator.getLastKnownPosition();
          }
        } catch (_) {}
      }

      if (posToSend != null) {
        await _sendTrackingPayload(pos: posToSend, isHeartbeat: true);
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _positionStreamSub?.cancel();
    _positionStreamSub = null;
    await sendOfflineSignal();
  }
}

void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_BgTaskHandler());
}

/// Minta pengecualian battery optimization (sekali, dialog sistem standar
/// Android 6+). Berlaku semua HP; yang agresif (Xiaomi/OPPO/Vivo) tetap bisa
/// membunuh service kalau user menolak — di luar kendali app.
Future<void> _requestBatteryOptimizationExempt() async {
  try {
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) return;
    await Permission.ignoreBatteryOptimizations.request();
  } catch (e) {
    print('[BG TRACK] request battery optimization gagal: $e');
  }
}

/// Start foreground service (jalankan sekali setelah login).
Future<void> startBackgroundTracking() async {
  try {
    if (await FlutterForegroundTask.isRunningService) return; // sudah jalan

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      print('[BG TRACK] izin lokasi ditolak, service belum di-start');
      return;
    }

    await _requestBatteryOptimizationExempt();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'tower_control_tracking',
        channelName: 'Tracking Armada',
        channelDescription: 'Notifikasi saat posisi armada sedang di-track',
      ),
      iosNotificationOptions: IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000), // Heartbeat setiap 60 detik (saat diam/macet)
        autoRunOnBoot: true, // restart service otomatis setelah HP reboot
        allowWakeLock: true, // CPU bangun saat event/stream
        allowWifiLock: true, // WiFi/sinyal hidup biar data terkirim
      ),
    );
    FlutterForegroundTask.initCommunicationPort();
    await FlutterForegroundTask.startService(
      serviceId: 2010,
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: 'Tower Control',
      notificationText: 'Tracking posisi berjalan di latar belakang',
      callback: _startCallback,
    );
    // Lapis 2: schedule alarm watchdog (5 menit) — biar service yang di-kill
    // ROM bisa restart sendiri walau app di-recent-cleared.
    await _scheduleWatchdogAlarm();
  } catch (e) {
    print('[BG TRACK] start gagal: $e');
  }
}

/// Stop foreground service — panggil saat logout.
Future<void> stopBackgroundTracking() async {
  try {
    await FlutterForegroundTask.stopService();
  } catch (e) {
    print('[BG TRACK] stop gagal: $e');
  }
  await _cancelWatchdogAlarm();
}

/// Watchdog: pastikan service tracking jalan selagi app masih terbuka.
/// Kalau service di-kill OS (battery saver agresif), restart otomatis —
/// selama user masih login.
/// Panggil periodik dari UI (misal tiap 30 detik).
Future<void> ensureTrackingRunning() async {
  try {
    if (await FlutterForegroundTask.isRunningService) return;

    final token = await ApiClient.getToken();
    if (token == null || token.isEmpty) return; // belum login → jangan start

    final cfg = await ApiClient.loadDriverConfig();
    var idDriver = cfg['id_driver'] as int? ?? 0;
    var idKendaraan = cfg['id_kendaraan'] as int? ?? 0;
    final role = (cfg['role'] ?? '').toString().trim().toLowerCase();
    final idUser = cfg['id_user'] as int? ?? 0;
    if (role == 'driver_pickup') {
      if (idDriver <= 0) idDriver = (idUser > 0 ? idUser : 39);
      if (idKendaraan <= 0) idKendaraan = 18;
    }
    if (idDriver <= 0 || idKendaraan <= 0) return; // identitas belum lengkap

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

    await startBackgroundTracking();
  } catch (e) {
    print('[BG TRACK] watchdog gagal: $e');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Watchdog Alarm (Lapis 2) — jalan di level SISTEM Android, bukan di dalam app.
// Kalau service foreground di-kill ROM agresif (XOS/MIUI/ColorOS), alarm tetap
// kebangun tiap 5 menit → cek service → kalau mati, restart otomatis.
// Ini jaring pengaman: app di-recent-cleared / service di-kill → ≤5 menit LIVE
// lagi. (Gagal total hanya kalau app di-force-stop manual dari Settings —
// batasan Android yang tidak bisa diakali app mana pun.)
// ─────────────────────────────────────────────────────────────────────────────

const _kWatchdogAlarmId = 1001;

/// Callback alarm watchdog — dieksekusi di isolate terpisah oleh sistem.
/// WAJIB `@pragma('vm:entry-point')` biar gak di-tree-shake di release build.
/// Setelah ngecek service, langsung re-schedule alarm berikutnya (rantai
/// one-shot) — lebih tahan dibanding periodic (yang bisa dibuang ROM agresif).
@pragma('vm:entry-point')
Future<void> alarmWatchdogCallback() async {
  print('[BG TRACK] alarm watchdog kebangun');
  await ensureTrackingRunning();
  await _scheduleWatchdogAlarm();
}

/// Schedule alarm watchdog one-shot exact (5 menit). Idempoten: cancel dulu
/// biar gak numpuk kalau dipanggil berulang (dari UI watchdog & guide izin).
///
/// Kenapa one-shot + re-schedule, bukan `periodic`?
/// `AndroidAlarmManager.periodic()` di balik layar pakai `setRepeating()` /
/// `setInexactRepeating()` yang TIDAK exact — di Doze & ROM agresif
/// (XOS/MIUI) alarm bisa ditunda/dibuang, watchdog mati diam-diam. One-shot
/// exact + `allowWhileIdle` jauh lebih bandel, dan tiap kebangun langsung
/// jadwalin lagi buat menit berikutnya.
Future<void> _scheduleWatchdogAlarm() async {
  try {
    await AndroidAlarmManager.initialize();
    await AndroidAlarmManager.cancel(_kWatchdogAlarmId);

    // Coba exact dulu (Android 12+ butuh SCHEDULE_EXACT_ALARM — manifest
    // sudah deklarasi). Kalau diizinkan, pakai exact+allowWhileIdle biar
    // bandel di Doze & ROM agresif. Kalau ditolak (exception), fallback ke
    // alarm biasa (best-effort).
    var scheduled = false;
    try {
      scheduled = await AndroidAlarmManager.oneShot(
        const Duration(minutes: 5),
        _kWatchdogAlarmId,
        alarmWatchdogCallback,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
      );
    } catch (e) {
      print('[BG TRACK] exact alarm ditolak, fallback biasa: $e');
    }
    if (!scheduled) {
      await AndroidAlarmManager.oneShot(
        const Duration(minutes: 5),
        _kWatchdogAlarmId,
        alarmWatchdogCallback,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
      );
    }
    print('[BG TRACK] alarm watchdog one-shot di-schedule (5 menit)');
  } catch (e) {
    print('[BG TRACK] schedule alarm gagal: $e');
  }
}

Future<void> _cancelWatchdogAlarm() async {
  try {
    await AndroidAlarmManager.cancel(_kWatchdogAlarmId);
    print('[BG TRACK] alarm watchdog di-cancel');
  } catch (e) {
    print('[BG TRACK] cancel alarm gagal: $e');
  }
}