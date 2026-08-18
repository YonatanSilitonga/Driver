import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Gaya dialog standar aplikasi — biar SEMUA modal konsisten:
/// - Radius 16, judul ikon + teks bold, konten rapi
/// - Tombol sekunder (batal) = TextButton abu-abu
/// - Tombol aksi = FilledButton berwarna (orange = CTA umum,
///   merah = aksi destruktif seperti logout/keluar)
///
/// Cara pakai:
/// ```dart
/// final ok = await AppDialog.confirm(
///   context: context,
///   icon: Icons.logout_rounded,
///   iconColor: AppColors.error,
///   title: 'Konfirmasi Logout',
///   message: 'Yakin mau keluar?',
///   actionLabel: 'Keluar',
///   destructive: true,
/// );
/// ```
class AppDialog {
  AppDialog._();

  /// Dialog konfirmasi sederhana (judul + pesan + batal + aksi).
  /// Return `true` kalau tombol aksi ditekan.
  static Future<bool?> confirm({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    Color iconColor = AppColors.orange,
    Color actionColor = AppColors.orange,
    bool destructive = false,
    String cancelLabel = 'Batal',
  }) {
    final actionBg = destructive ? AppColors.error : actionColor;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        title: Row(
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              cancelLabel,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: actionBg,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Dialog custom penuh — buat kasus yang butuh konten khusus
  /// (form, daftar langkah, dll). Pastikan konten punya `mainAxisSize.min`
  /// atau dibungkus scroll biar gak overflow di HP kecil.
  static Future<T?> show<T>({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Widget content,
    required List<Widget> actions,
    Color iconColor = AppColors.orange,
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        title: Row(
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: content,
        actions: actions,
      ),
    );
  }

  /// Dialog custom + state lokal (misal tombol loading). Konten & actions
  /// dibangun lewat `builder(ctx, setDialogState)` — setDialogState buat
  /// rebuild tombol (misal spinner saat proses).
  static Future<T?> showStateful<T>({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Widget Function(BuildContext ctx, StateSetter setState) builder,
    Color iconColor = AppColors.orange,
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          title: Row(
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: builder(ctx, setDialogState),
          ),
        ),
      ),
    );
  }

  /// Tombol aksi standar dialog — FilledButton (CTA umum / destruktif).
  static Widget actionButton({
    required String label,
    required VoidCallback onPressed,
    Color color = AppColors.orange,
    bool destructive = false,
  }) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: destructive ? AppColors.error : color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  /// Tombol batal standar dialog — TextButton abu-abu.
  static Widget cancelButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}