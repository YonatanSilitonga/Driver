import 'package:intl/intl.dart';

/// Mendapatkan waktu sekarang di zona waktu WIB (UTC+7) secara presisi
DateTime nowWIB() {
  // Mengambil waktu utc saat ini lalu ditambah 7 jam murni tanpa terpengaruh device local
  final nowUtc = DateTime.now().toUtc();
  return nowUtc.add(const Duration(hours: 7));
}

/// Konversi [DateTime] ke WIB dengan aman
DateTime toWIB(DateTime dt) {
  // Jika dt sudah memiliki waktu lokal, pastikan dikonversi akurat ke WIB
  return dt.toUtc().add(const Duration(hours: 7));
}

/// Format datetime ke string WIB: "31 Jul 2026, 14:30"
String formatDateTimeWIB(DateTime dt) {
  final wib = toWIB(dt);
  return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(wib);
}

/// Format datetime ke string WIB: "31 Jul 2026"
String formatDateWIB(DateTime dt) {
  final wib = toWIB(dt);
  return DateFormat('dd MMM yyyy', 'id_ID').format(wib);
}

/// Format datetime ke string WIB: "14:30"
String formatTimeWIB(DateTime dt) {
  final wib = toWIB(dt);
  return DateFormat('HH:mm').format(wib);
}

/// Format datetime ke string WIB compact: "2026-08-22"
String formatDateISO_WIB(DateTime dt) {
  final wib = toWIB(dt);
  return DateFormat('yyyy-MM-dd').format(wib);
}

/// Mengembalikan tanggal hari ini format "YYYY-MM-DD" murni waktu WIB
String todayISO_WIB() {
  return formatDateISO_WIB(DateTime.now());
}

String? parseAndFormatDateTimeWIB(String? isoString) {
  if (isoString == null || isoString.isEmpty) return null;
  final dt = DateTime.tryParse(isoString);
  if (dt == null) return null;
  return formatDateTimeWIB(dt);
}

String? parseAndFormatDateWIB(String? isoString) {
  if (isoString == null || isoString.isEmpty) return null;
  final dt = DateTime.tryParse(isoString);
  if (dt == null) return null;
  return formatDateWIB(dt);
}

String? parseAndFormatTimeWIB(String? isoString) {
  if (isoString == null || isoString.isEmpty) return null;
  final dt = DateTime.tryParse(isoString);
  if (dt == null) return null;
  return formatTimeWIB(dt);
}