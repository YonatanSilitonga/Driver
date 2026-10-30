import 'package:dio/dio.dart';
import 'api_client.dart';

class PickupService {
  /// Simpan muatan dari satu seller (single pickup item)
  static Future<void> savePickupBarang({
    required int idUser,
    required String namaDriver,
    required String asalSeller,
    required int jumlahBarang,
    int highValue = 0,
    int koli = 0,
    int ecer = 0,
    required String status, // 'menuju_seller' | 'menuju_gudang' | 'standby' | 'selesai'
    String catatan = '',
    String? fotoUrl,
  }) async {
    try {
      final response = await ApiClient.dio.post(
        '/armada/pickup/barang',
        data: {
          'id_user': idUser,
          'nama_driver': namaDriver,
          'asal_seller': asalSeller,
          'jumlah_barang': jumlahBarang,
          'high_value': highValue,
          'koli': koli,
          'ecer': ecer,
          'status': status,
          'catatan': catatan,
          'foto_url': fotoUrl ?? '',
        },
      );

      final body = response.data;
      if (body is Map && body['success'] == false) {
        throw body['message'] ?? 'Gagal menyimpan data pickup';
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] ?? e.message ?? 'Koneksi bermasalah';
      throw msg;
    } catch (e) {
      throw e.toString();
    }
  }

  /// Ambil riwayat penjemputan driver pickup (bisa filter per tanggal YYYY-MM-DD)
  static Future<List<Map<String, dynamic>>> getPickupHistory(int idUser, {String? tanggal}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (tanggal != null && tanggal.isNotEmpty) {
        queryParams['tanggal'] = tanggal;
      }
      final response = await ApiClient.dio.get(
        '/armada/pickup/$idUser/history',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      final body = response.data;
      if (body is Map && body['success'] == true) {
        final list = body['data'];
        if (list is List) {
          return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
