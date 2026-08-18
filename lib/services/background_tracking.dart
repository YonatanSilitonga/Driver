// ignore_for_file: avoid_print

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
final _kBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://humble-pretext-crock.ngrok-free.dev/api/v1',
);

/// Dio khusus background — pakai token dari penyimpanan (WAJIB, endpoint /driver/* JWT).
Future<Dio> _bgDio() async {
  final dio = Dio(BaseOptions(
    baseUrl: _kBaseUrl,
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12),
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

/// Kirim heartbeat posisi ke backend dari background (layar mati / di-background).
/// Hitung kecepatan dari delta posisi antar-heartbeat (GPS hardware speed
/// sering 0 saat layar mati) biar dashboard gak selalu "Berhenti".
double? _prevBgLat;
double? _prevBgLng;
DateTime? _prevBgTime;

Future<void> _sendHeartbeat() async {
  try {
    final cfg = await ApiClient.loadDriverConfig();
    final idDriver = cfg['id_driver'] as int? ?? 0;
    final idKendaraan = cfg['id_kendaraan'] as int? ?? 0;
    if (idDriver <= 0 || idKendaraan <= 0) return; // identitas belum lengkap

    final token = await ApiClient.getToken();
    if (token == null || token.isEmpty) return; // belum login → jangan kirim

    final pos = await Geolocator.getCurrentPosition();
    final idRitase = cfg['id_ritase'] as int? ?? 0;

    // Speed: pakai speed hardware kalau valid (>0), fallback hitung dari
    // delta posisi antar-heartbeat (distanceBetween / delta waktu * 3.6).
    var speedKmh = (pos.speed < 0 ? 0.0 : pos.speed * 3.6).round();
    final now = DateTime.now();
    if (speedKmh == 0 &&
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
        speedKmh = ((distM / dtSec) * 3.6).round();
      }
    }
    _prevBgLat = pos.latitude;
    _prevBgLng = pos.longitude;
    _prevBgTime = now;

    final dio = await _bgDio();
    await _postWithRetry(dio, {
      'id_driver': idDriver,
      'id_kendaraan': idKendaraan,
      'id_ritase': idRitase,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'kecepatan': speedKmh,
      'status': 'Background',
      'durasi_detik': 0,
    });
  } catch (e) {
    print('[BG TRACKING] gagal: $e');
  }
}

/// Sinyal "app/service berhenti" → backend langsung cap kendaraan OFFLINE.
/// Best-effort (onDestroy force-stop Android tidak selalu dipanggil).
/// Publik supaya bisa dipanggil eksplisit dari UI (misal konfirmasi keluar app).
Future<void> sendOfflineSignal() async {
  try {
    final cfg = await ApiClient.loadDriverConfig();
    final idDriver = cfg['id_driver'] as int? ?? 0;
    final idKendaraan = cfg['id_kendaraan'] as int? ?? 0;
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
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _sendHeartbeat();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _sendHeartbeat();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Service berhenti → kasih tau backend biar truk langsung OFF.
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

    // Wajib izin "Always" — tanpa ini Android blokir GPS saat layar mati
    // (background location) dan service cuma jalan sia-sia.
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always) {
      print('[BG TRACK] izin lokasi belum "Always", service belum di-start');
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
        eventAction: ForegroundTaskEventAction.repeat(30000), // 30 detik
        autoRunOnBoot: true, // restart service otomatis setelah HP reboot
        allowWakeLock: true, // CPU tetep bangun pas layar mati (default true, eksplisit)
        allowWifiLock: true, // WiFi/sinyal tetep hidup pas layar mati biar data terkirim
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
/// selama izin "Always" masih aktif & user masih login.
/// Panggil periodik dari UI (misal tiap 30 detik).
Future<void> ensureTrackingRunning() async {
  try {
    if (await FlutterForegroundTask.isRunningService) return;

    final token = await ApiClient.getToken();
    if (token == null || token.isEmpty) return; // belum login → jangan start

    final cfg = await ApiClient.loadDriverConfig();
    final idDriver = cfg['id_driver'] as int? ?? 0;
    final idKendaraan = cfg['id_kendaraan'] as int? ?? 0;
    if (idDriver <= 0 || idKendaraan <= 0) return; // identitas belum lengkap

    // Izin "Always" wajib — tanpa ini service jalan sia-sia (Android blokir GPS
    // saat layar mati).
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always) return;

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