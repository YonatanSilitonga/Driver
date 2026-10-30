import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_client.dart';
import '../../services/pickup_service.dart';

class PickupFormScreen extends StatefulWidget {
  final int idUser;
  final String namaDriver;
  final String currentStatus;

  const PickupFormScreen({
    super.key,
    required this.idUser,
    required this.namaDriver,
    this.currentStatus = 'standby',
  });

  @override
  State<PickupFormScreen> createState() => _PickupFormScreenState();
}

class _PickupFormScreenState extends State<PickupFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _sellerController = TextEditingController();
  final _awbController = TextEditingController();
  final _hvController = TextEditingController(text: '0');
  final _catatanController = TextEditingController();

  final _scrollController = ScrollController();
  int _savedCount = 0;
  bool _isSubmitting = false;
  File? _pickedImage;
  final ImagePicker _imagePicker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 70,
      );
      if (file != null) {
        setState(() {
          _pickedImage = File(file.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memilih foto: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _sellerController.dispose();
    _awbController.dispose();
    _hvController.dispose();
    _catatanController.dispose();
    super.dispose();
  }

  Future<void> _submitData(String targetStatus) async {
    final seller = _sellerController.text.trim();
    final awbText = _awbController.text.trim();
    final isToGudang = targetStatus == 'menuju_gudang';

    // Jika ingin kembali ke gudang dan form kosong (seller belum diisi),
    // artinya driver sudah selesai input seller-seller sebelumnya dan langsung ingin kembali ke gudang
    if (isToGudang && seller.isEmpty) {
      setState(() => _isSubmitting = true);
      try {
        await PickupService.savePickupBarang(
          idUser: widget.idUser,
          namaDriver: widget.namaDriver,
          asalSeller: 'Perjalanan ke Gudang',
          jumlahBarang: 0,
          highValue: 0,
          koli: 0,
          ecer: 0,
          status: 'menuju_gudang',
          catatan: 'Kembali ke gudang',
        );
        await ApiClient.savePickupStatus('menuju_gudang');

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.warehouse_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Status diperbarui: Menuju Gudang.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.of(context).pop('menuju_gudang');
      } catch (e) {
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal perbarui status: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final awb = int.tryParse(awbText) ?? 0;
    final hv = int.tryParse(_hvController.text.trim()) ?? 0;
    final catatan = _catatanController.text.trim();

    setState(() => _isSubmitting = true);

    String? photoUrl;
    if (_pickedImage != null) {
      try {
        photoUrl = await ApiClient.uploadManifestPhoto(
          idRitase: 0,
          filePath: _pickedImage!.path,
          namaLokasi: seller,
        );
      } catch (err) {
        // ignore: avoid_print
        print('⚠️ Gagal upload foto manifest: $err');
      }
    }

    try {
      await PickupService.savePickupBarang(
        idUser: widget.idUser,
        namaDriver: widget.namaDriver,
        asalSeller: seller,
        jumlahBarang: awb,
        highValue: hv,
        koli: 0,
        ecer: 0,
        status: targetStatus,
        catatan: catatan,
        fotoUrl: photoUrl,
      );
      await ApiClient.savePickupStatus(targetStatus);

      if (!mounted) return;

      if (isToGudang) {
        // Kembali ke tampilan awal dengan status menuju_gudang
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Muatan "$seller" tersimpan! Perjalanan kembali ke gudang.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.of(context).pop('menuju_gudang');
      } else {
        // Menuju Seller Berikutnya: Reset form agar langsung muncul form lagi untuk input seller berikutnya
        _savedCount++;
        _sellerController.clear();
        _awbController.clear();
        _hvController.text = '0';
        _catatanController.clear();
        _pickedImage = null;
        _formKey.currentState?.reset();

        setState(() => _isSubmitting = false);

        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Muatan "$seller" tersimpan! Silakan input seller ke-${_savedCount + 1}.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Gagal simpan: $e',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.of(context).pop(_savedCount > 0 ? 'menuju_seller' : null),
        ),
        title: Text(
          _savedCount > 0 ? 'Input Muatan Seller (${_savedCount + 1})' : 'Input Muatan Seller',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFF1F5F9), height: 1),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Input 1: Nama Seller
                      const Text(
                        'Nama Seller / Toko *',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _sellerController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          hintText: 'Contoh: Toko Berkah / Gudang Elektronik',
                          prefixIcon: const Icon(Icons.storefront_rounded, color: Color(0xFFF27D26), size: 20),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFF27D26), width: 1.8),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Nama seller wajib diisi';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 18),

                      // Input 2: Jumlah AWB
                      const Text(
                        'Jumlah AWB (Paket) *',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _awbController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: '0',
                          suffixText: 'AWB',
                          prefixIcon: const Icon(Icons.inventory_2_rounded, color: Color(0xFFF27D26), size: 20),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFF27D26), width: 1.8),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Jumlah AWB wajib diisi';
                          }
                          final num = int.tryParse(value);
                          if (num == null || num < 0) {
                            return 'Jumlah AWB tidak valid';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 18),

                      // Input 3: High Value
                      const Text(
                        'Paket High Value (Bernilai Tinggi)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _hvController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          hintText: '0',
                          suffixText: 'Paket',
                          prefixIcon: const Icon(Icons.verified_rounded, color: Color(0xFFDC2626), size: 20),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.8),
                          ),
                        ),
                      ),



                      const SizedBox(height: 18),

                      // Input Catatan Opsional
                      const Text(
                        'Catatan (Opsional)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _catatanController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Contoh: Sebagian paket masih dikemas',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Foto Bukti Manifest / Scan (Opsional)
                      const Text(
                        'Foto Bukti Scan / Manifest (Opsional)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_pickedImage == null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _isSubmitting ? null : () => _pickImage(ImageSource.gallery),
                                      icon: const Icon(Icons.photo_library_rounded, size: 20, color: Color(0xFFF27D26)),
                                      label: const Text(
                                        'Pilih dari Galeri',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        backgroundColor: Colors.white,
                                        side: const BorderSide(color: Color(0xFFF27D26), width: 1.4),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: _isSubmitting ? null : () => _pickImage(ImageSource.camera),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      backgroundColor: Colors.white,
                                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: const Icon(Icons.camera_alt_rounded, size: 20, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Pilih foto hasil scan / resi bukti yang tersimpan di galeri HP',
                                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF27D26), width: 1.2),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  _pickedImage!,
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                  cacheWidth: 200,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Foto Bukti Dipilih',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _pickedImage!.path.split(RegExp(r'[\\/]')).last,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                                tooltip: 'Hapus Foto',
                                onPressed: _isSubmitting ? null : () => setState(() => _pickedImage = null),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── 2 TOMBOL AKSI BAWAH ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tombol 1: Menuju Seller Berikutnya
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _isSubmitting ? null : () => _submitData('menuju_seller'),
                        icon: const Icon(Icons.alt_route_rounded, size: 20),
                        label: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text(
                                'Menuju Seller Berikutnya',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Tombol 2: Kembali ke Gudang
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _isSubmitting ? null : () => _submitData('menuju_gudang'),
                        icon: const Icon(Icons.warehouse_rounded, size: 20),
                        label: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text(
                                'Kembali ke Gudang',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
