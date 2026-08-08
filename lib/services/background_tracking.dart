// ignore_for_file: avoid_print

import 'package:dio/dio.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import 'api_client.dart';

/// Background tracking (foreground service) — flutter_foreground_task v10.
/// Identitas driver/kendaraan/ritase diambil dari config yang sudah disimpan
/// oleh `ApiClient.saveDriverConfig` (login & saat trip mulai).
/// Integrasi:
///   - Login sukses → `startBackgroundTracking()`
///   - Logout → `stopBackgroundTracking()`
///   - Android 10+: izin "Izinkan semua waktu" diaktifkan manual di Settings.
///   - HP Xiaomi/OPPO/Vivo: exempt dari battery optimization biar gak di-kill.
const _kBaseUrl = 'https://violator-krypton-image.ngrok-free.dev/api/v1';

/// Kirim heartbeat posisi ke backend dari background (layar mati / di-background).
Future<void> _sendHeartbeat() async {
  try {
    final cfg = await ApiClient.loadDriverConfig();
    final idDriver = cfg['id_driver'] as int? ?? 0;
    final idKendaraan = cfg['id_kendaraan'] as int? ?? 0;
    if (idDriver <= 0 || idKendaraan <= 0) return; // identitas belum lengkap

    final pos = await Geolocator.getCurrentPosition();
    final idRitase = cfg['id_ritase'] as int? ?? 0;

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
      'id_ritase': idRitase,
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

void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_BgTaskHandler());
}

/// Start foreground service (jalankan sekali setelah login).
Future<void> startBackgroundTracking() async {
  try {
    if (await FlutterForegroundTask.isRunningService) return; // sudah jalan
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
}