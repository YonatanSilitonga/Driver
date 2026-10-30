import 'package:flutter/foundation.dart';

/// Konfigurasi environment aplikasi.
///
/// Nilai diambil dari `--dart-define` / `--dart-define-from-file` saat build.
/// Default sengaja diarahkan ke production agar build tanpa konfigurasi tidak
/// pernah menembak IP lokal yang sudah tidak berlaku.
class AppConfig {
  static const String _rawApiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.controltowerslb.tech/api/v1',
  );

  static const String _rawApiFallbackUrl = String.fromEnvironment(
    'API_URL_FALLBACK',
    defaultValue: '',
  );

  static const bool isProduction = bool.fromEnvironment(
    'PRODUCTION',
    defaultValue: true,
  );

  static String get apiUrl => _normalize(_rawApiUrl);

  static String get apiFallbackUrl => _normalize(_rawApiFallbackUrl);

  /// Fallback hanya boleh dipakai di development, tidak untuk production.
  static bool get enableNetworkFallback =>
      !isProduction && apiFallbackUrl.isNotEmpty && apiFallbackUrl != apiUrl;

  static void validate() {
    _validateUrl(apiUrl, name: 'API_URL', requireHttps: isProduction);

    if (isProduction && apiFallbackUrl.isNotEmpty) {
      throw StateError(
        'API_URL_FALLBACK tidak boleh diisi untuk build production.',
      );
    }

    if (apiFallbackUrl.isNotEmpty) {
      _validateUrl(
        apiFallbackUrl,
        name: 'API_URL_FALLBACK',
        requireHttps: false,
      );
    }

    if (isProduction && _isPrivateHost(Uri.parse(apiUrl).host)) {
      throw StateError(
        'API_URL production tidak boleh memakai host lokal/privat: $apiUrl',
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[CONFIG] PRODUCTION=$isProduction API_URL=$apiUrl '
        'FALLBACK=${apiFallbackUrl.isEmpty ? '-' : apiFallbackUrl}',
      );
    }
  }

  static String _normalize(String value) {
    final trimmed = value.trim();
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }

  static void _validateUrl(
    String value, {
    required String name,
    required bool requireHttps,
  }) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw StateError('$name tidak valid: "$value"');
    }

    if (requireHttps && uri.scheme != 'https') {
      throw StateError('$name wajib memakai HTTPS untuk production: $value');
    }
  }

  static bool _isPrivateHost(String host) {
    final normalized = host.toLowerCase();
    if (normalized == 'localhost' ||
        normalized == '::1' ||
        normalized == '0.0.0.0') {
      return true;
    }

    final parts = normalized.split('.');
    if (parts.length != 4) return false;

    final octets = parts.map(int.tryParse).toList(growable: false);
    if (octets.any((octet) => octet == null || octet < 0 || octet > 255)) {
      return false;
    }

    final first = octets[0]!;
    final second = octets[1]!;
    return first == 10 ||
        first == 127 ||
        (first == 192 && second == 168) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 169 && second == 254);
  }
}
