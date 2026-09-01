import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';

enum NetworkErrorType {
  noInternet,
  timeout,
  serverError,
  unauthorized,
  notFound,
  badRequest,
  unknown,
}

class NetworkException implements Exception {
  final String message;
  final NetworkErrorType type;
  final int? statusCode;
  final dynamic originalError;

  const NetworkException({
    required this.message,
    this.type = NetworkErrorType.unknown,
    this.statusCode,
    this.originalError,
  });

  bool get isNoInternet => type == NetworkErrorType.noInternet;
  bool get isTimeout => type == NetworkErrorType.timeout;
  bool get isServerError => type == NetworkErrorType.serverError;

  @override
  String toString() => message;

  /// Parse exception apa pun (DioException, SocketException, TimeoutException, dll)
  /// menjadi pesan Bahasa Indonesia yang ramah bagi pengguna mobile.
  factory NetworkException.from(dynamic error) {
    if (error is NetworkException) return error;

    if (error is DioException) {
      return _fromDioException(error);
    }

    if (error is SocketException) {
      return NetworkException(
        message: 'Tidak ada koneksi internet. Periksa WiFi atau data seluler Anda.',
        type: NetworkErrorType.noInternet,
        originalError: error,
      );
    }

    if (error is TimeoutException) {
      return NetworkException(
        message: 'Koneksi ke server timeout. Silakan coba beberapa saat lagi.',
        type: NetworkErrorType.timeout,
        originalError: error,
      );
    }

    if (error is FormatException) {
      return NetworkException(
        message: 'Format data dari server tidak valid.',
        type: NetworkErrorType.badRequest,
        originalError: error,
      );
    }

    final rawStr = error?.toString() ?? '';
    if (rawStr.toLowerCase().contains('socket') ||
        rawStr.toLowerCase().contains('network is unreachable') ||
        rawStr.toLowerCase().contains('failed host lookup')) {
      return NetworkException(
        message: 'Tidak dapat terhubung ke internet. Periksa koneksi Anda.',
        type: NetworkErrorType.noInternet,
        originalError: error,
      );
    }

    return NetworkException(
      message: 'Terjadi kendala pada sistem. Silakan coba lagi.',
      type: NetworkErrorType.unknown,
      originalError: error,
    );
  }

  static NetworkException _fromDioException(DioException e) {
    // 1. Cek response message dari backend jika ada
    final respData = e.response?.data;
    String? backendMessage;
    if (respData is Map) {
      backendMessage = respData['message']?.toString() ??
          respData['error']?.toString() ??
          respData['msg']?.toString();
    } else if (respData is String && respData.isNotEmpty) {
      // Jika string pendek (bukan HTML page)
      if (!respData.trim().startsWith('<') && respData.length < 120) {
        backendMessage = respData;
      }
    }

    final statusCode = e.response?.statusCode;

    // 2. Berdasarkan Type DioException
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkException(
          message: 'Koneksi ke server timeout. Jaringan Anda mungkin sedang lambat.',
          type: NetworkErrorType.timeout,
          statusCode: statusCode,
          originalError: e,
        );

      case DioExceptionType.connectionError:
        return NetworkException(
          message: 'Tidak dapat terhubung ke server. Pastikan Anda memiliki koneksi internet yang stabil.',
          type: NetworkErrorType.noInternet,
          statusCode: statusCode,
          originalError: e,
        );

      case DioExceptionType.badCertificate:
        return NetworkException(
          message: 'Koneksi aman gagal diverifikasi. Periksa tanggal & jam HP Anda.',
          type: NetworkErrorType.unknown,
          statusCode: statusCode,
          originalError: e,
        );

      case DioExceptionType.cancel:
        return NetworkException(
          message: 'Permintaan dibatalkan.',
          type: NetworkErrorType.unknown,
          statusCode: statusCode,
          originalError: e,
        );

      case DioExceptionType.badResponse:
        if (statusCode != null) {
          if (statusCode == 401) {
            return NetworkException(
              message: backendMessage ?? 'Sesi Anda telah berakhir. Silakan login kembali.',
              type: NetworkErrorType.unauthorized,
              statusCode: statusCode,
              originalError: e,
            );
          }
          if (statusCode == 403) {
            return NetworkException(
              message: backendMessage ?? 'Anda tidak memiliki akses untuk tindakan ini.',
              type: NetworkErrorType.unauthorized,
              statusCode: statusCode,
              originalError: e,
            );
          }
          if (statusCode == 404) {
            return NetworkException(
              message: backendMessage ?? 'Data yang dicari tidak ditemukan.',
              type: NetworkErrorType.notFound,
              statusCode: statusCode,
              originalError: e,
            );
          }
          if (statusCode >= 400 && statusCode < 500) {
            return NetworkException(
              message: backendMessage ?? 'Permintaan tidak dapat diproses. Periksa data Anda.',
              type: NetworkErrorType.badRequest,
              statusCode: statusCode,
              originalError: e,
            );
          }
          if (statusCode >= 500) {
            return NetworkException(
              message: backendMessage ?? 'Server sedang mengalami gangguan (Error $statusCode). Silakan coba lagi nanti.',
              type: NetworkErrorType.serverError,
              statusCode: statusCode,
              originalError: e,
            );
          }
        }
        break;

      case DioExceptionType.unknown:
      default:
        if (e.error is SocketException ||
            e.message?.toLowerCase().contains('socket') == true ||
            e.message?.toLowerCase().contains('network is unreachable') == true ||
            e.message?.toLowerCase().contains('failed host lookup') == true) {
          return NetworkException(
            message: 'Tidak ada koneksi internet. Periksa WiFi atau data seluler Anda.',
            type: NetworkErrorType.noInternet,
            statusCode: statusCode,
            originalError: e,
          );
        }
        break;
    }

    return NetworkException(
      message: backendMessage ?? 'Terjadi kesalahan pada jaringan. Silakan coba lagi.',
      type: NetworkErrorType.unknown,
      statusCode: statusCode,
      originalError: e,
    );
  }
}
