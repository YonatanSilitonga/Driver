import 'dart:developer' as dev;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'schedule_reminders';
  static const String channelName = 'Pengingat Jadwal Ritase';
  static const String channelDescription =
      'Notifikasi pengingat H-30 menit dan H-5 menit sebelum jadwal rute dimulai';

  static Future<void> init() async {
    try {
      tz.initializeTimeZones();
      // Set timezone lokal (Asia/Jakarta / WIB)
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
      } catch (_) {
        tz.setLocalLocation(tz.local);
      }

      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          dev.log('Notification tapped: ${response.payload}', name: 'NotificationService');
        },
      );

      // Buat Android Notification Channel dengan prioritas tinggi
      final AndroidNotificationChannel channel = AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(channel);
        await androidPlugin.requestNotificationsPermission();
        await androidPlugin.requestExactAlarmsPermission();
      }

      dev.log('NotificationService initialized successfully', name: 'NotificationService');
    } catch (e) {
      dev.log('Failed to initialize NotificationService: $e', name: 'NotificationService');
    }
  }

  /// Format string jam HH:MM:SS atau HH:MM menjadi HH:MM
  static String _formatJam(String jam) {
    final parts = jam.split(':');
    if (parts.length >= 2) {
      return '${parts[0]}:${parts[1]}';
    }
    return jam;
  }

  /// Menjadwalkan pengingat H-30 menit dan H-5 menit untuk jadwal ritase
  static Future<void> scheduleRitaseReminders({
    required int idRitase,
    required String kodeRitase,
    required int ritaseKe,
    required String jamMulai,
    required String tanggal,
  }) async {
    try {
      if (idRitase <= 0 || jamMulai.isEmpty || tanggal.isEmpty) return;

      // Parsing Tanggal & Jam Mulai (e.g. "2026-09-03" & "12:00:00")
      final dateParts = tanggal.split('-');
      final timeParts = jamMulai.split(':');
      if (dateParts.length < 3 || timeParts.length < 2) return;

      final year = int.tryParse(dateParts[0]) ?? DateTime.now().year;
      final month = int.tryParse(dateParts[1]) ?? DateTime.now().month;
      final day = int.tryParse(dateParts[2]) ?? DateTime.now().day;
      final hour = int.tryParse(timeParts[0]) ?? 0;
      final minute = int.tryParse(timeParts[1]) ?? 0;

      final scheduleDateTime = DateTime(year, month, day, hour, minute);
      final now = DateTime.now();

      final jamFormatted = _formatJam(jamMulai);

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true,
        enableVibration: true,
      );

      const NotificationDetails notificationDetails =
          NotificationDetails(android: androidDetails);

      // ── 1. Pengingat H-30 Menit ──
      final timeH30 = scheduleDateTime.subtract(const Duration(minutes: 30));
      if (timeH30.isAfter(now)) {
        final tzH30 = tz.TZDateTime.from(timeH30, tz.local);
        final idH30 = (idRitase * 10) + 1;

        await _notificationsPlugin.zonedSchedule(
          idH30,
          '🔔 Pengingat Jadwal: Ritase $ritaseKe',
          'Jadwal ritase $kodeRitase akan dimulai dalam 30 menit ($jamFormatted). Segera persiapkan armada dan cek muatan.',
          tzH30,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'ritase_$idRitase',
        );
        dev.log('Scheduled H-30 reminder for $kodeRitase at $timeH30', name: 'NotificationService');
      }

      // ── 2. Pengingat H-5 Menit ──
      final timeH5 = scheduleDateTime.subtract(const Duration(minutes: 5));
      if (timeH5.isAfter(now)) {
        final tzH5 = tz.TZDateTime.from(timeH5, tz.local);
        final idH5 = (idRitase * 10) + 2;

        await _notificationsPlugin.zonedSchedule(
          idH5,
          '⚠️ Ritase $ritaseKe Dimulai 5 Menit Lagi!',
          'Jadwal $kodeRitase dimulai pukul $jamFormatted. Silakan bersiap dan mulai perjalanan Anda.',
          tzH5,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'ritase_$idRitase',
        );
        dev.log('Scheduled H-5 reminder for $kodeRitase at $timeH5', name: 'NotificationService');
      }
    } catch (e) {
      dev.log('Error scheduling ritase reminders: $e', name: 'NotificationService');
    }
  }

  /// Membatalkan pengingat untuk ID ritase tertentu (saat trip selesai/batal)
  static Future<void> cancelRitaseReminders(int idRitase) async {
    try {
      if (idRitase <= 0) return;
      await _notificationsPlugin.cancel((idRitase * 10) + 1);
      await _notificationsPlugin.cancel((idRitase * 10) + 2);
      dev.log('Cancelled reminders for ritase ID: $idRitase', name: 'NotificationService');
    } catch (e) {
      dev.log('Error cancelling reminders: $e', name: 'NotificationService');
    }
  }

  /// Menampilkan notifikasi langsung (instant)
  static Future<void> showInstant({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const NotificationDetails details =
          NotificationDetails(android: androidDetails);

      await _notificationsPlugin.show(
        DateTime.now().millisecond,
        title,
        body,
        details,
        payload: payload,
      );
    } catch (e) {
      dev.log('Error showing instant notification: $e', name: 'NotificationService');
    }
  }
}
