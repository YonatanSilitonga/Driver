import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_client.dart';

class AppUpdater {
  static bool _isDialogShowing = false;

  /// Versi aplikasi saat ini.
  /// WAJIB diubah setiap kali rilis versi baru (sama dengan VersionName di handlers.go).
  static const String currentAppVersion = "1.0.9";

  /// Cek versi aplikasi ke server & tampilkan dialog jika versi server beda.
  static Future<void> checkUpdate(BuildContext context, {bool isManual = false}) async {
    if (isManual) {
      _isDialogShowing = false; // Reset lock saat cek manual
    }

    if (_isDialogShowing) return;

    if (isManual && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Memeriksa pembaruan aplikasi...'),
            ],
          ),
          duration: Duration(seconds: 1),
        ),
      );
    }

    try {
      final info = await ApiClient.checkAppVersion();
      if (!context.mounted) return;
      if (info == null) {
        if (isManual) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gagal memeriksa pembaruan. Periksa koneksi internet.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final serverVersionName = info['version_name']?.toString().trim() ?? '';

      // Perbandingan teks versi langsung (100% bebas bug split-per-abi):
      // Jika versi server BEDA dengan versi di kode ini -> Tampilkan dialog update
      final isUpdateAvailable = serverVersionName.isNotEmpty && serverVersionName != currentAppVersion;

      // ignore: avoid_print
      print('🔄 [APP UPDATER] App: v$currentAppVersion vs Server: v$serverVersionName (Update? $isUpdateAvailable)');

      if (isUpdateAvailable) {
        final downloadUrl = info['download_url']?.toString() ?? '';
        final releaseNotes = info['release_notes']?.toString() ??
            'Pembaruan performa & fitur baru tersedia.';
        final forceUpdate = info['force_update'] == true;

        if (!context.mounted) return;

        _isDialogShowing = true;
        try {
          await showDialog(
            context: context,
            barrierDismissible: !forceUpdate,
            builder: (ctx) => PopScope(
              canPop: !forceUpdate,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.system_update_rounded, color: Color(0xFF0D47A1), size: 28),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Pembaruan Aplikasi',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Versi $serverVersionName sudah tersedia!',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      releaseNotes,
                      style: TextStyle(color: Colors.grey[800], fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
                actions: [
                  if (!forceUpdate)
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Nanti', style: TextStyle(color: Colors.grey)),
                    ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                    label: const Text(
                      'Perbarui Sekarang',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      if (downloadUrl.isNotEmpty) {
                        if (!forceUpdate) {
                          Navigator.pop(ctx);
                        }
                        try {
                          final uri = Uri.parse(downloadUrl);
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Gagal membuka link unduhan: $e')),
                            );
                          }
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        } finally {
          _isDialogShowing = false;
        }
      } else if (isManual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Aplikasi sudah menggunakan versi terbaru (v$currentAppVersion).',
            ),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      _isDialogShowing = false;
      if (isManual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memeriksa pembaruan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
