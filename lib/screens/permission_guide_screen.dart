import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/background_tracking.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_dialog.dart';

/// Guide "Persiapan Tracking" — ngarahin driver biar izin-izin wajib beneran
/// kepasang (lokasi "Selalu", battery unrestricted, notifikasi, autostart).
/// Muncul sekali setelah login & bisa dibuka manual dari menu ⋮ di dashboard.
class PermissionGuideScreen extends StatefulWidget {
  const PermissionGuideScreen({super.key});

  /// Tampilkan guide SEKALI (pertama kali setelah install/login).
  /// Panggil dari login & splash sebelum navigasi ke Home. Return true
  /// kalau guide benar-benar ditampilkan.
  static Future<bool> maybeShowOnce(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'permission_guide_seen';
    if (prefs.getBool(key) ?? false) return false;
    if (!context.mounted) return false;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PermissionGuideScreen()),
    );
    // Flag di-set SETELAH guide ditutup (selesai ATAU dilewati) — kalau user
    // kill app di tengah guide, masih muncul lagi di bukaan berikutnya.
    await prefs.setBool(key, true);
    return true;
  }

  @override
  State<PermissionGuideScreen> createState() => _PermissionGuideScreenState();
}

class _PermissionGuideScreenState extends State<PermissionGuideScreen> {
  bool _checking = true;
  bool _locationAlways = false;
  bool _batteryUnrestricted = false;
  bool _notificationGranted = false;
  bool _autostartDone = false;

  static const _kAutostartPref = 'permission_guide_autostart_done';

  @override
  void initState() {
    super.initState();
    _checkAll();
  }

  Future<void> _checkAll() async {
    setState(() => _checking = true);

    final loc = await Geolocator.checkPermission();
    final batt = await Permission.ignoreBatteryOptimizations.status;
    final notif = await Permission.notification.status;
    final prefs = await SharedPreferences.getInstance();
    final auto = prefs.getBool(_kAutostartPref) ?? false;

    if (!mounted) return;
    setState(() {
      _locationAlways = loc == LocationPermission.always;
      _batteryUnrestricted = batt.isGranted;
      _notificationGranted = notif.isGranted;
      _autostartDone = auto;
      _checking = false;
    });
  }

  int get _readyCount {
    var n = 0;
    if (_locationAlways) n++;
    if (_batteryUnrestricted) n++;
    if (_notificationGranted) n++;
    if (_autostartDone) n++;
    return n;
  }

  Future<void> _fixLocation() async {
    // Panduan langkah biar driver nggak bingung cari menu-nya.
    if (!mounted) return;
    final go = await AppDialog.show(
      context: context,
      icon: Icons.location_on_rounded,
      iconColor: AppColors.navy,
      title: 'Aktifkan Lokasi "Semua Waktu"',
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepRow(no: '1', text: 'Buka menu "Izin" / "Permissions"'),
            _StepRow(no: '2', text: 'Tap "Lokasi" / "Location"'),
            _StepRow(
              no: '3',
              text: 'Pilih "Izinkan semua waktu" / "Allow all the time"',
            ),
            SizedBox(height: 10),
            Text(
              'Catatan: di HP Xiaomi menu-nya bisa beda-beda, tapi cari '
              'bagian "Izin lokasi" lalu pilih yang paling longgar '
              '(All the time).',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        AppDialog.cancelButton(
          label: 'Batal',
          onPressed: () => Navigator.pop(context, false),
        ),
        AppDialog.actionButton(
          label: 'Buka Pengaturan',
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (go != true) return;

    await Geolocator.openAppSettings();
    // Balik dari settings → cek ulang.
    await _checkAll();
  }

  Future<void> _fixBattery() async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (!status.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }
    await _checkAll();
  }

  Future<void> _fixNotification() async {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
    if (!(await Permission.notification.status).isGranted) {
      await openAppSettings();
    }
    await _checkAll();
  }

  Future<void> _fixAutostart() async {
    final prefs = await SharedPreferences.getInstance();
    // Tidak ada API publik buat cek "Izin Latar Belakang" per merk — driver
    // pilih merk HP-nya di dialog, baca langkahnya, lalu konfirmasi "Sudah".
    if (!mounted) return;
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ManufacturerGuideDialog(),
    );
    if (done == true) {
      await prefs.setBool(_kAutostartPref, true);
      if (!mounted) return;
      await _checkAll();
    }
  }

  Future<void> _finish() async {
    // Selesai → pastikan service tracking jalan (no-op kalau izin belum selalu).
    try {
      await startBackgroundTracking();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final allReady = _readyCount == 4;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text('Persiapan Tracking'),
        elevation: 0,
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header status
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: allReady ? AppColors.successBg : AppColors.warningBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: allReady ? AppColors.success : AppColors.warning,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        allReady
                            ? Icons.check_circle_rounded
                            : Icons.warning_amber_rounded,
                        color: allReady ? AppColors.success : AppColors.warning,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              allReady
                                  ? 'Semua izin sudah pas!'
                                  : '$_readyCount dari 4 izin selesai',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              allReady
                                  ? 'Tracking armada siap jalan penuh, termasuk saat layar HP mati.'
                                  : 'Lengkapi izin di bawah biar posisi armada tetap terpantau.',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Lokasi ──
                _buildItem(
                  icon: Icons.location_on_rounded,
                  title: 'Lokasi: Izinkan Semua Waktu',
                  desc: _locationAlways
                      ? 'Sudah "Always" — tracking tetap jalan saat layar mati.'
                      : 'Pilih "Izinkan semua waktu" (Allow all the time) di '
                          'pengaturan lokasi MUSTGO.',
                  done: _locationAlways,
                  onFix: _fixLocation,
                ),

                // ── Battery ──
                _buildItem(
                  icon: Icons.battery_charging_full_rounded,
                  title: 'Optimasi Baterai: Tanpa Batasan',
                  desc: _batteryUnrestricted
                      ? 'Baterai "Unrestricted" — service tidak dibunuh sistem.'
                      : 'Set "Unrestricted" / "Tanpa batasan" biar service '
                          'tracking tidak dimatikan sistem.',
                  done: _batteryUnrestricted,
                  onFix: _fixBattery,
                ),

                // ── Notifikasi ──
                _buildItem(
                  icon: Icons.notifications_active_rounded,
                  title: 'Notifikasi Tracking Aktif',
                  desc: _notificationGranted
                      ? 'Notifikasi diizinkan — status tracking terlihat jelas.'
                      : 'Izinkan notifikasi (channel "Tracking Armada") biar '
                          'driver tahu tracking sedang berjalan.',
                  done: _notificationGranted,
                  onFix: _fixNotification,
                ),

                // ── Izin Latar Belakang (semua merk) ──
                _buildItem(
                  icon: Icons.autorenew_rounded,
                  title: 'Izin Latar Belakang (semua merk)',
                  desc: _autostartDone
                      ? 'Settingan background HP sudah diatur — service aman '
                          'dari pembersih aplikasi.'
                      : 'Atur biar HP tidak membunuh service tracking di '
                          'latar belakang (beda-beda per merk).',
                  done: _autostartDone,
                  onFix: _fixAutostart,
                ),

                const SizedBox(height: 20),

                // ── Aksi ──
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _checking ? null : _checkAll,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.navy,
                          side: const BorderSide(color: AppColors.navy),
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Cek Lagi'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _checking ? null : _finish,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: Icon(
                          allReady
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                        ),
                        label: Text(allReady ? 'Selesai' : 'Lanjut Saja'),
                      ),
                    ),
                  ],
                ),
                if (!allReady) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Bisa dilewati, tapi tracking berhenti saat layar mati '
                    'kalau izin belum lengkap.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildItem({
    required IconData icon,
    required String title,
    required String desc,
    required bool done,
    required VoidCallback onFix,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: done ? AppColors.success : AppColors.borderLight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: done ? AppColors.successBg : AppColors.warningBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: done ? AppColors.success : AppColors.warning),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      done
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      size: 20,
                      color: done ? AppColors.success : AppColors.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
                if (!done) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: onFix,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navy,
                        side: const BorderSide(color: AppColors.navy),
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: const Text('Atur'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Baris langkah panduan (nomor + teks) di dialog lokasi.
class _StepRow extends StatelessWidget {
  final String no;
  final String text;
  const _StepRow({required this.no, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.navy,
              shape: BoxShape.circle,
            ),
            child: Text(
              no,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog panduan "Izin Latar Belakang" — tampilkan langkah SEMUA merk HP
/// (expandable). Driver cari merk-nya, ikuti langkah, lalu konfirmasi "Sudah".
class _ManufacturerGuideDialog extends StatefulWidget {
  const _ManufacturerGuideDialog();

  @override
  State<_ManufacturerGuideDialog> createState() =>
      _ManufacturerGuideDialogState();
}

class _ManufacturerGuideDialogState extends State<_ManufacturerGuideDialog> {
  final Set<String> _expanded = {};

  static const _steps = <String, List<String>>{
    'Xiaomi / Redmi / POCO': [
      'Buka Pengaturan → Aplikasi → Kelola aplikasi',
      'Pilih MUSTGO',
      'Buka "Autostart" / "Mulai otomatis" → AKTIFKAN',
      'Buka "Penghemat baterai" → pilih "Tanpa batasan"',
    ],
    'Samsung': [
      'Buka Pengaturan → Aplikasi → MUSTGO',
      'Buka "Baterai"',
      'Pilih "Tanpa batasan" (Unrestricted)',
      'Pengaturan → Perawatan baterai → Batas penggunaan latar belakang → '
          'Aplikasi tidur / tidur nyenyak → PASTIKAN MUSTGO TIDAK ada di sana',
    ],
    'Huawei / Honor': [
      'Buka Pengaturan → Baterai → Peluncuran aplikasi',
      'Pilih MUSTGO → pilih "Kelola secara manual"',
      'Aktifkan "Peluncuran otomatis" & "Aktivitas latar belakang"',
    ],
    'OPPO / Realme / OnePlus': [
      'Buka Pengaturan → Aplikasi → MUSTGO → Penggunaan baterai',
      'Aktifkan "Izinkan aktivitas latar belakang"',
      'Matikan "Optimasi otomatis" / "Pembatas" buat app ini',
    ],
    'Vivo': [
      'Buka Pengaturan → Aplikasi → Kelola aplikasi → MUSTGO',
      'Buka "Mulai otomatis" → AKTIFKAN',
      'Buka "Batasan konsumsi daya latar belakang" → izinkan',
    ],
    'Infinix / Tecno': [
      'Buka Pengaturan → Aplikasi → Kelola aplikasi → MUSTGO',
      'Buka "Baterai" → pilih "Tanpa batasan" (No restrictions)',
      'Aktifkan "Izinkan aktivitas latar belakang"',
      'Pengaturan → Baterai → Manajemen Daya (Power Management) → '
          'izinkan MUSTGO / matikan pembatasan kalau ada',
      'Auto-start (opsional): Pengaturan → Manajemen aplikasi → '
          '"Manajemen mulai otomatis" → AKTIFKAN MUSTGO. Kalau menu ini '
          'tidak ada di HP kamu, LEWATI saja — yang wajib cuma langkah '
          'baterai "Tanpa batasan" di atas.',
      'Matikan mode "Penghemat daya" / "Smart Battery" kalau aktif',
      'Kunci app biar gak ke-clean: buka Recent apps → tekan & tahan kartu '
          'MUSTGO → pilih "Kunci" (ikon gembok 🔒)',
    ],
    'Nokia / Motorola / Google': [
      'Stock Android — cukup izin lokasi "Semua waktu" & baterai '
          '"Tanpa batasan" yang sudah diatur di langkah sebelumnya.',
      'Tidak perlu langkah tambahan.',
    ],
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      title: const Row(
        children: [
          Icon(
            Icons.smartphone_rounded,
            color: AppColors.navy,
            size: 24,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Izin Latar Belakang',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pilih merk HP kamu, ikuti langkahnya. Ini biar sistem tidak '
              'membunuh service tracking saat layar mati. Tips: setelah selesai, '
              'kunci app dari Recent apps (ikon gembok) biar gak ke-clean.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _steps.entries.map((entry) {
                  final brand = entry.key;
                  final steps = entry.value;
                  final isOpen = _expanded.contains(brand);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: AppColors.borderLight),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setState(() {
                          if (isOpen) {
                            _expanded.remove(brand);
                          } else {
                            _expanded.add(brand);
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.smartphone_rounded,
                                  size: 18,
                                  color: AppColors.navy,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    brand,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                Icon(
                                  isOpen
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  size: 20,
                                  color: AppColors.textMuted,
                                ),
                              ],
                            ),
                            if (isOpen) ...[
                              const SizedBox(height: 10),
                              ...steps.map(
                                (s) => _StepRow(
                                  no: '${steps.indexOf(s) + 1}',
                                  text: s,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        AppDialog.cancelButton(
          label: 'Belum',
          onPressed: () => Navigator.pop(context, false),
        ),
        AppDialog.actionButton(
          label: 'Sudah, lanjut',
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}