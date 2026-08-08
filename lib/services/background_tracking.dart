// ignore_for_file: avoid_print

import 'package:dio/dio.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Background tracking (foreground service) — flutter_foreground_task v10.
/// Integrasi (menyusul saat merge):
///   - Saat login sukses / ritase dimulai: `saveTrackingIdentity(...)` lalu `startBackgroundTracking()`.
///   - Saat logout: `stopBackgroundTracking()` + `clearTrackingIdentity()`.
/// Catatan Android 10+: izin "Izinkan semua waktu" diaktifkan manual di Settings.
const _kIdDriver = 'bg_id_driver';
const _kIdKendaraan = 'bg_id_kendaraan';
const _kIdRitase = 'bg_id_ritase';
const _kBaseUrl = 'https://violator-krypton-image.ngrok-free.dev/api/v1';

/// Simpan identitas driver/kendaraan saat ritase dimulai (dipanggil dari Home).
Future<void> saveTrackingIdentity({
  required int idDriver,
  required int idKendaraan,
  int? idRitase,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kIdDriver, idDriver);
  await prefs.setInt(_kIdKendaraan, idKendaraan);
  if (idRitase != null) await prefs.setInt(_kIdRitase, idRitase);
}

Future<void> clearTrackingIdentity() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kIdDriver);
  await prefs.remove(_kIdKendaraan);
  await prefs.remove(_kIdRitase);
}

/// Kirim heartbeat posisi ke backend dari background.
Future<void> _sendHeartbeat() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final idDriver = prefs.getInt(_kIdDriver);
    final idKendaraan = prefs.getInt(_kIdKendaraan);
    if (idDriver == null || idKendaraan == null) return;

    final pos = await Geolocator.getCurrentPosition();
    final idRitase = prefs.getInt(_kIdRitase);

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
    await dio.post('/driver/tracking', data: {
      'id_driver': idDriver,
      'id_kendaraan': idKendaraan,
      'id_ritase': idRitase ?? 0,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'kecepatan': 0,
      'status': 'Background',
      'durasi_detik': 0,
    });
  } catch (e) {
    print('[BG TRACKING] gagal: $e');
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
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Callback untuk startService — meregistrasi TaskHandler.
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_BgTaskHandler());
}

/// Start foreground service — panggil setelah login / saat mulai ritase.
Future<void> startBackgroundTracking() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'tower_control_tracking',
      channelName: 'Tracking Armada',
      channelDescription: 'Notifikasi saat posisi armada sedang di-track',
    ),
    iosNotificationOptions: IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(30000), // 30 detik
      autoRunOnBoot: false,
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
}

/// Stop foreground service — panggil saat logout.
Future<void> stopBackgroundTracking() async {
  await FlutterForegroundTask.stopService();
}
