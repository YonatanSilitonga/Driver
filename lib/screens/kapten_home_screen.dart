import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'kapten_confirm_screen.dart';
import 'login_screen.dart';

class KaptenHomeScreen extends StatefulWidget {
  const KaptenHomeScreen({super.key});

  @override
  State<KaptenHomeScreen> createState() => _KaptenHomeScreenState();
}

class _KaptenHomeScreenState extends State<KaptenHomeScreen> {
  String _driverName = 'Kapten';
  String _sellerName = '';
  int _currentSellerId = 0;
  List<Map<String, dynamic>> _sellers = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isSwitching = false;
  String? _error;
  String? _successMsg;

  // Data sebelumnya (untuk info card)
  int _prevAwb = 0;
  int _prevKoliJkt = 0, _prevKoliSeg = 0, _prevKoliBtn = 0;
  int _prevEcerJkt = 0, _prevEcerSeg = 0, _prevEcerBtn = 0;
  int _prevKoliHvJkt = 0, _prevKoliHvSeg = 0, _prevKoliHvBtn = 0;
  int _prevEcerHvJkt = 0, _prevEcerHvSeg = 0, _prevEcerHvBtn = 0;
  bool _isOldData = false;

  // Controllers — 13 input fields
  final _awbController = TextEditingController(text: '0');
  final _koliJktController = TextEditingController(text: '0');
  final _koliSegController = TextEditingController(text: '0');
  final _koliBtnController = TextEditingController(text: '0');
  final _ecerJktController = TextEditingController(text: '0');
  final _ecerSegController = TextEditingController(text: '0');
  final _ecerBtnController = TextEditingController(text: '0');
  final _koliHvJktController = TextEditingController(text: '0');
  final _koliHvSegController = TextEditingController(text: '0');
  final _koliHvBtnController = TextEditingController(text: '0');
  final _ecerHvJktController = TextEditingController(text: '0');
  final _ecerHvSegController = TextEditingController(text: '0');
  final _ecerHvBtnController = TextEditingController(text: '0');
  String? _fotoPath;
  final _catatanController = TextEditingController();

  // Ritase selection
  int _ritaseKe = 1;
  List<int> _activeRitases = [];
  String? _noRitaseMessage;

  /// Jumlah grup input yang menunggu konfirmasi driver (badge AppBar)
  int _pendingCount = 0;

  /// Sisa per grup hari ini (dari konfirmasi-penjemputan) — kartu "Data saat
  /// ini" menampilkan SISA, bukan total input.
  List<Map<String, dynamic>> _sisaGrup = [];

  int _toInt(dynamic v) => (v as num?)?.toInt() ?? 0;

  /// Entri sisa untuk Rit aktif (jenis selalu outgoing di layar ini).
  Map<String, dynamic>? _sisaRit() {
    for (final s in _sisaGrup) {
      if ((s['jenis_ritase'] ?? '') == 'outgoing' && _toInt(s['ritase_ke']) == _ritaseKe) {
        return s;
      }
    }
    return null;
  }

  void _zeroPrev() {
    _prevAwb = 0;
    _prevKoliJkt = 0; _prevKoliSeg = 0; _prevKoliBtn = 0;
    _prevEcerJkt = 0; _prevEcerSeg = 0; _prevEcerBtn = 0;
    _prevKoliHvJkt = 0; _prevKoliHvSeg = 0; _prevKoliHvBtn = 0;
    _prevEcerHvJkt = 0; _prevEcerHvSeg = 0; _prevEcerHvBtn = 0;
    _isOldData = false;
    _sisaGrup = [];
  }

  List<TextEditingController> get _allControllers => [
    _awbController, _koliJktController, _koliSegController, _koliBtnController,
    _ecerJktController, _ecerSegController, _ecerBtnController,
    _koliHvJktController, _koliHvSegController, _koliHvBtnController,
    _ecerHvJktController, _ecerHvSegController, _ecerHvBtnController,
    _catatanController,
  ];

  @override
  void initState() {
    super.initState();
    _detectActiveRitases();
    _loadInitialData();
  }

  /// Hitung ritase yang sedang aktif berdasarkan waktu sekarang.
  /// Rit 1: 00:00-19:59, Rit 2: 16:00-23:59, Rit 3: 20:00-03:00
  void _detectActiveRitases() {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final active = <int>[];

    // Rit 1: 00:00 - 19:59 (0 - 1199 menit)
    if (nowMin >= 0 && nowMin <= 1199) active.add(1);
    // Rit 2: 16:00 - 23:59 (960 - 1439 menit)
    if (nowMin >= 960 && nowMin <= 1439) active.add(2);
    // Rit 3: 20:00 - 03:00 (1200-1439 + 0-180, cross-midnight)
    if (nowMin >= 1200 || nowMin <= 180) active.add(3);

    setState(() {
      _activeRitases = active;
      if (active.isEmpty) {
        _noRitaseMessage = 'Tidak ada jadwal ritase aktif';
        _ritaseKe = 0;
      } else {
        _noRitaseMessage = null;
        _ritaseKe = active.first;
      }
    });
  }

  @override
  void dispose() {
    for (final c in _allControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final cfg = await ApiClient.loadDriverConfig();
      _driverName = cfg['driver_name'] ?? 'Kapten';

      _currentSellerId = await ApiClient.getSellerId();

      final results = await Future.wait([
        ApiClient.fetchKaptenSellerInfo(),
        ApiClient.getMySellers(),
        ApiClient.fetchPendingConfirmations(),
      ]);

      final sellerInfo = results[0] as Map<String, dynamic>?;
      if (sellerInfo != null) {
        _sellerName = sellerInfo['nama_seller'] ?? '';
      }

      final sellers = results[1] as List<Map<String, dynamic>>;
      _sellers = sellers;

      final pending = results[2] as List<Map<String, dynamic>>;
      _pendingCount = pending.length;

      await _fetchRitData();
    } catch (e) {
      // Ignore error for seller info
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Ambil data milik Rit aktif: total input (today-cargo) + sisa grup.
  /// Dipanggil saat buka layar, ganti tab Rit, setelah submit, dan setelah
  /// kembali dari Konfirmasi Pengambilan.
  Future<void> _fetchRitData() async {
    Map<String, dynamic>? todayData;
    List<Map<String, dynamic>> sisaGrup = [];
    try {
      final results = await Future.wait([
        ApiClient.fetchTodayCargo(jenisRitase: 'outgoing', ritaseKe: _ritaseKe),
        ApiClient.fetchKonfirmasiPenjemputan(),
      ]);
      todayData = results[0];
      final kd = results[1];
      final sg = kd?['sisa_grup'];
      if (sg is List) sisaGrup = List<Map<String, dynamic>>.from(sg);
    } catch (_) {
      // Abaikan — kartu memakai fallback data lama
      if (!mounted) return;
      return;
    }
    if (!mounted) return;
    setState(() {
      if (todayData != null) {
        _prevAwb = (todayData['jumlah_awb'] as num?)?.toInt() ?? 0;
        _prevKoliJkt = (todayData['koli_jkt'] as num?)?.toInt() ?? 0;
        _prevKoliSeg = (todayData['koli_seg'] as num?)?.toInt() ?? 0;
        _prevKoliBtn = (todayData['koli_btn'] as num?)?.toInt() ?? 0;
        _prevEcerJkt = (todayData['ecer_jkt'] as num?)?.toInt() ?? 0;
        _prevEcerSeg = (todayData['ecer_seg'] as num?)?.toInt() ?? 0;
        _prevEcerBtn = (todayData['ecer_btn'] as num?)?.toInt() ?? 0;
        _prevKoliHvJkt = (todayData['koli_hv_jkt'] as num?)?.toInt() ?? 0;
        _prevKoliHvSeg = (todayData['koli_hv_seg'] as num?)?.toInt() ?? 0;
        _prevKoliHvBtn = (todayData['koli_hv_btn'] as num?)?.toInt() ?? 0;
        _prevEcerHvJkt = (todayData['ecer_hv_jkt'] as num?)?.toInt() ?? 0;
        _prevEcerHvSeg = (todayData['ecer_hv_seg'] as num?)?.toInt() ?? 0;
        _prevEcerHvBtn = (todayData['ecer_hv_btn'] as num?)?.toInt() ?? 0;
        _isOldData = todayData['is_ada_data'] == true;
      }
      _sisaGrup = sisaGrup;
    });
  }

  /// Refresh badge pending tanpa reload seluruh layar.
  Future<void> _refreshPendingCount() async {
    try {
      final pending = await ApiClient.fetchPendingConfirmations();
      if (mounted) setState(() => _pendingCount = pending.length);
    } catch (_) {
      // Abaikan — badge hanya info tambahan
    }
  }

  bool _hasUnsavedData() {
    for (final c in _allControllers) {
      if ((int.tryParse(c.text) ?? 0) > 0) return true;
    }
    return _fotoPath != null;
  }

  void _showSellerPicker() {
    if (_sellers.length <= 1) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Ganti Implant',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              ..._sellers.map((s) {
                final id = s['id_seller'] as int? ?? 0;
                final name = s['nama_seller'] ?? '-';
                final kode = s['kode_seller'] ?? '';
                final isActive = id == _currentSellerId;
                return ListTile(
                  leading: Icon(
                    Icons.store_rounded,
                    color: isActive ? const Color(0xFFFEA103) : const Color(0xFF94A3B8),
                  ),
                  title: Text(name, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.w500)),
                  subtitle: kode.isNotEmpty ? Text(kode, style: const TextStyle(fontSize: 12)) : null,
                  trailing: isActive
                      ? const Icon(Icons.check_circle, color: Color(0xFFFEA103))
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    if (!isActive) _switchSeller(id);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _switchSeller(int newSellerId) async {
    if (_hasUnsavedData()) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Data Belum Tersimpan'),
          content: const Text('Ada data muatan yang belum dikirim. Ganti implant?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFEA103)),
              child: const Text('Ganti'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _isSwitching = true);

    try {
      final result = await ApiClient.selectSeller(newSellerId);
      if (result != null && mounted) {
        final token = result['token'] as String?;
        if (token != null && token.isNotEmpty) {
          await ApiClient.saveToken(token);
          await ApiClient.saveSellerId(newSellerId);

          for (final c in _allControllers) {
            c.text = '0';
          }
          _fotoPath = null;

          await _loadInitialData();

          if (mounted) {
            setState(() {
              _currentSellerId = newSellerId;
              _isSwitching = false;
              // Pesan sukses/error milik seller lama ikut dibersihkan.
              _successMsg = null;
              _error = null;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSwitching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal ganti implant: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickFoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 70,
    );
    if (picked != null) {
      setState(() => _fotoPath = picked.path);
    }
  }

  int _ctrl(TextEditingController c) => int.tryParse(c.text) ?? 0;

  Future<void> _submit() async {
    if (_isSubmitting) return;

    // Tutup keyboard + snackbar lama di awal (bukan setelah await).
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (_ritaseKe == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada jadwal ritase aktif'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
      return;
    }

    final awb = _ctrl(_awbController);
    final koliJkt = _ctrl(_koliJktController);
    final koliSeg = _ctrl(_koliSegController);
    final koliBtn = _ctrl(_koliBtnController);
    final ecerJkt = _ctrl(_ecerJktController);
    final ecerSeg = _ctrl(_ecerSegController);
    final ecerBtn = _ctrl(_ecerBtnController);
    final koliHvJkt = _ctrl(_koliHvJktController);
    final koliHvSeg = _ctrl(_koliHvSegController);
    final koliHvBtn = _ctrl(_koliHvBtnController);
    final ecerHvJkt = _ctrl(_ecerHvJktController);
    final ecerHvSeg = _ctrl(_ecerHvSegController);
    final ecerHvBtn = _ctrl(_ecerHvBtnController);

    final totalInput = awb + koliJkt + koliSeg + koliBtn +
        ecerJkt + ecerSeg + ecerBtn +
        koliHvJkt + koliHvSeg + koliHvBtn +
        ecerHvJkt + ecerHvSeg + ecerHvBtn;

    if (totalInput == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Minimal isi salah satu jumlah muatan'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
      return;
    }

    // Konfirmasi ritase
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi Ritase'),
        content: Text(
          'Anda akan mengirim data muatan untuk Ritase $_ritaseKe.\n\n'
          'Apakah ritase sudah sesuai?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFEA103)),
            child: const Text('Ya, Kirim'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _isSubmitting = true;
      _successMsg = null;
      _error = null;
    });

    try {
      String? fotoUrl;
      if (_fotoPath != null) {
        fotoUrl = await ApiClient.uploadManifestPhoto(
          idRitase: 0,
          filePath: _fotoPath!,
          namaLokasi: _sellerName,
        );
      }

      final result = await ApiClient.submitKaptenCargo(
        idRitase: 0,
        idStop: 0,
        jenisRitase: 'outgoing',
        ritaseKe: _ritaseKe,
        jumlahAwb: awb,
        koliJkt: koliJkt, koliSeg: koliSeg, koliBtn: koliBtn,
        ecerJkt: ecerJkt, ecerSeg: ecerSeg, ecerBtn: ecerBtn,
        koliHvJkt: koliHvJkt, koliHvSeg: koliHvSeg, koliHvBtn: koliHvBtn,
        ecerHvJkt: ecerHvJkt, ecerHvSeg: ecerHvSeg, ecerHvBtn: ecerHvBtn,
        namaLokasi: _sellerName,
        fotoManifestUrl: fotoUrl,
        catatan: _catatanController.text.trim(),
      );

      if (result != null && mounted) {
        final isUpdated = result['is_updated'] == true;

        // Refresh data Rit aktif (input + sisa) dari API
        await _fetchRitData();

        setState(() {
          _isOldData = true;
          _successMsg = isUpdated ? 'Data berhasil diupdate!' : 'Data muatan berhasil disimpan!';
          _isSubmitting = false;
          _fotoPath = null;
        });
        for (final c in _allControllers) {
          c.text = c == _catatanController ? '' : '0';
        }

        // Input baru = pending baru → refresh badge konfirmasi
        _refreshPendingCount();
        // Pop-up sukses (ganti SnackBar agar tidak tertutup keyboard).
        if (mounted) _showSuccessDialog(isUpdated);
      } else if (mounted) {
        setState(() {
          _error = 'Gagal menyimpan data muatan';
          _isSubmitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isSubmitting = false;
        });
      }
    }
  }

  /// Pop-up sukses setelah input tersimpan: ringkasan total akumulasi
  /// seller + Rit aktif. Satu tombol Selesai untuk menutup.
  Future<void> _showSuccessDialog(bool isUpdated) async {
    final totalKoli = _prevKoliJkt + _prevKoliSeg + _prevKoliBtn;
    final totalEcer = _prevEcerJkt + _prevEcerSeg + _prevEcerBtn;
    final totalKoliHv = _prevKoliHvJkt + _prevKoliHvSeg + _prevKoliHvBtn;
    final totalEcerHv = _prevEcerHvJkt + _prevEcerHvSeg + _prevEcerHvBtn;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: Color(0xFF16A34A), size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isUpdated ? 'Data Berhasil Diupdate!' : 'Data Berhasil Disimpan!',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_sellerName.isNotEmpty)
              Text(
                '$_sellerName • Rit $_ritaseKe',
                style: const TextStyle(fontSize: 13, color: Color(0xFF475569), fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 8),
            const Text(
              'Total saat ini:',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildInfoChip('$_prevAwb AWB', const Color(0xFFEDE9FE), const Color(0xFF6D28D9)),
                _buildInfoChip('$totalKoli Koli', const Color(0xFFDBEAFE), const Color(0xFF1E40AF)),
                _buildInfoChip('$totalEcer Ecer', const Color(0xFFFEF9C3), const Color(0xFF854D0E)),
                _buildInfoChip('$totalKoliHv Koli HV', const Color(0xFFFEF3C7), const Color(0xFFB45309)),
                _buildInfoChip('$totalEcerHv Ecer HV', const Color(0xFFFFE7E7), const Color(0xFFC2410C)),
              ],
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Selesai', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('Yakin ingin keluar dari aplikasi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.exit_to_app_rounded, color: Color(0xFFDC2626)),
                SizedBox(width: 10),
                Text('Keluar Aplikasi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: const Text(
              'Apakah Anda yakin ingin keluar dari MustGo?',
              style: TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Keluar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (shouldExit == true) SystemNavigator.pop();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kapten: $_driverName',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (_sellerName.isNotEmpty)
              Text(
                _sellerName,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.assignment_turned_in_rounded),
                tooltip: 'Konfirmasi Pengambilan',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => KaptenConfirmScreen(sellerName: _sellerName),
                    ),
                  ).then((_) {
                    // Konfirmasi mengubah sisa → refresh badge + data Rit.
                    _refreshPendingCount();
                    _fetchRitData();
                  });
                },
              ),
              if (_pendingCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFDC2626),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      '$_pendingCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0D47A1)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Seller info card — tappable dropdown
                  if (_sellerName.isNotEmpty)
                    GestureDetector(
                      onTap: _sellers.length > 1 ? _showSellerPicker : null,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: _isSwitching
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: SizedBox(
                                    width: 24, height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0D47A1)),
                                  ),
                                ),
                              )
                            : Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFDBEAFE),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.store_rounded,
                                      color: Color(0xFF0D47A1),
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _sellerName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        const Text(
                                          'Seller Implant',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF0D47A1),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_sellers.length > 1)
                                    const Icon(Icons.unfold_more, color: Color(0xFF94A3B8), size: 20)
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'AKTIF',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF16A34A),
                                        ),
                                      ),
                                     ),
                                  ],
                                ),
                              ),
                      ),

                  const SizedBox(height: 20),

                  // Ritase selector
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pilih Ritase',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_noRitaseMessage != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.schedule, size: 18, color: Color(0xFF92400E)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _noRitaseMessage!,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF92400E),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          // Ritase tabs: selalu tampil 1-2-3, inactive = gray + lock
                          Row(
                            children: [1, 2, 3].map((ke) {
                              final isActive = _activeRitases.contains(ke);
                              final isSelected = _ritaseKe == ke;
                              return Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(right: ke != 3 ? 8 : 0),
                                  child: GestureDetector(
                                    onTap: isActive
                                        ? () {
                                            if (ke == _ritaseKe) return;
                                            // Bersihkan data + pesan Rit lama agar tidak bocor ke tab baru.
                                            setState(() {
                                              _ritaseKe = ke;
                                              _successMsg = null;
                                              _error = null;
                                              _zeroPrev();
                                            });
                                            _fetchRitData();
                                          }
                                        : null,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: !isActive
                                            ? Colors.grey.shade200
                                            : isSelected
                                                ? const Color(0xFFFEA103)
                                                : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: !isActive
                                              ? Colors.grey.shade300
                                              : isSelected
                                                  ? const Color(0xFFFEA103)
                                                  : const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: Center(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (!isActive) ...[
                                              Icon(Icons.lock_outline, size: 13, color: Colors.grey.shade500),
                                              const SizedBox(width: 4),
                                            ],
                                            Text(
                                              'Rit $ke',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: !isActive
                                                    ? Colors.grey.shade500
                                                    : isSelected
                                                        ? Colors.white
                                                        : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Form section — kartu putih pembungkus judul s.d. data saat ini
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Input Data Muatan',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Isi data barang yang masuk ke seller ini',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 16),

                        // Error message
                        if (_error != null)
                          _buildBanner(
                            icon: Icons.error_outline,
                            color: const Color(0xFFDC2626),
                            bgColor: const Color(0xFFFEF2F2),
                            borderColor: const Color(0xFFFECACA),
                            text: _error!,
                          ),

                        // Success message
                        if (_successMsg != null)
                          _buildBanner(
                            icon: Icons.check_circle_outline,
                            color: const Color(0xFF16A34A),
                            bgColor: const Color(0xFFF0FDF4),
                            borderColor: const Color(0xFF86EFAC),
                            text: _successMsg!,
                          ),

                        // Info data sebelumnya
                        if (_isOldData)
                          _buildPreviousDataCard(),
                      ],
                    ),
                  ),

                  // Input AWB
                  _buildInputField(
                    controller: _awbController,
                    label: 'Jumlah AWB',
                    icon: Icons.receipt_long_outlined,
                    color: const Color(0xFF6366F1),
                  ),
                  const SizedBox(height: 16),

                  // === Section KOLI ===
                  _buildSectionHeader('Koli', Icons.inventory_2_outlined, const Color(0xFF0D47A1)),
                  _buildRowInputs([
                    _FieldDef(_koliJktController, 'JKT', const Color(0xFF0D47A1)),
                    _FieldDef(_koliSegController, 'SEG', const Color(0xFF0284C7)),
                    _FieldDef(_koliBtnController, 'BTN', const Color(0xFF0369A1)),
                  ]),
                  const SizedBox(height: 16),

                  // === Section ECER ===
                  _buildSectionHeader('Ecer', Icons.shopping_bag_outlined, const Color(0xFF16A34A)),
                  _buildRowInputs([
                    _FieldDef(_ecerJktController, 'JKT', const Color(0xFF16A34A)),
                    _FieldDef(_ecerSegController, 'SEG', const Color(0xFF15803D)),
                    _FieldDef(_ecerBtnController, 'BTN', const Color(0xFF166534)),
                  ]),
                  const SizedBox(height: 16),

                  // === Section KOLI HV ===
                  _buildSectionHeader('Koli HV', Icons.star_outline, const Color(0xFFF59E0B)),
                  _buildRowInputs([
                    _FieldDef(_koliHvJktController, 'JKT', const Color(0xFFF59E0B)),
                    _FieldDef(_koliHvSegController, 'SEG', const Color(0xFFD97706)),
                    _FieldDef(_koliHvBtnController, 'BTN', const Color(0xFFB45309)),
                  ]),
                  const SizedBox(height: 16),

                  // === Section ECER HV ===
                  _buildSectionHeader('Ecer HV', Icons.star_half_outlined, const Color(0xFFEA580C)),
                  _buildRowInputs([
                    _FieldDef(_ecerHvJktController, 'JKT', const Color(0xFFEA580C)),
                    _FieldDef(_ecerHvSegController, 'SEG', const Color(0xFFC2410C)),
                    _FieldDef(_ecerHvBtnController, 'BTN', const Color(0xFF9A3412)),
                  ]),
                  const SizedBox(height: 16),

                  // Foto section
                  _buildFotoSection(),
                  const SizedBox(height: 16),

                  // Catatan (opsional)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.note_alt_outlined, size: 18, color: Colors.grey.shade600),
                            const SizedBox(width: 8),
                            Text(
                              'Catatan (opsional)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _catatanController,
                          maxLines: 3,
                          minLines: 2,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: 'Tambahkan catatan jika diperlukan...',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (_isSubmitting || _ritaseKe == 0 || !_activeRitases.contains(_ritaseKe)) ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D47A1),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.save_rounded, size: 22),
                                SizedBox(width: 8),
                                Text(
                                  'Simpan Data Muatan',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
    );
  }

  // ─── Helper Widgets ───

  Widget _buildBanner({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  /// Nilai tampil kartu "Data saat ini": SISA bila ada datanya,
  /// fallback ke total input bila data sisa gagal dimuat.
  Map<String, int> _dispValues() {
    final s = _sisaRit();
    int v(String? sisaKey, int fallback) =>
        s != null ? _toInt(s[sisaKey]) : fallback;
    return {
      'jumlah_awb': v('sisa_jumlah_awb', _prevAwb),
      'koli_jkt': v('sisa_koli_jkt', _prevKoliJkt),
      'koli_seg': v('sisa_koli_seg', _prevKoliSeg),
      'koli_btn': v('sisa_koli_btn', _prevKoliBtn),
      'ecer_jkt': v('sisa_ecer_jkt', _prevEcerJkt),
      'ecer_seg': v('sisa_ecer_seg', _prevEcerSeg),
      'ecer_btn': v('sisa_ecer_btn', _prevEcerBtn),
      'koli_hv_jkt': v('sisa_koli_hv_jkt', _prevKoliHvJkt),
      'koli_hv_seg': v('sisa_koli_hv_seg', _prevKoliHvSeg),
      'koli_hv_btn': v('sisa_koli_hv_btn', _prevKoliHvBtn),
      'ecer_hv_jkt': v('sisa_ecer_hv_jkt', _prevEcerHvJkt),
      'ecer_hv_seg': v('sisa_ecer_hv_seg', _prevEcerHvSeg),
      'ecer_hv_btn': v('sisa_ecer_hv_btn', _prevEcerHvBtn),
    };
  }

  Widget _buildPreviousDataCard() {
    final d = _dispValues();
    final awb = d['jumlah_awb']!;
    final totalKoli = d['koli_jkt']! + d['koli_seg']! + d['koli_btn']!;
    final totalEcer = d['ecer_jkt']! + d['ecer_seg']! + d['ecer_btn']!;
    final totalKoliHv = d['koli_hv_jkt']! + d['koli_hv_seg']! + d['koli_hv_btn']!;
    final totalEcerHv = d['ecer_hv_jkt']! + d['ecer_hv_seg']! + d['ecer_hv_btn']!;
    final allZero = awb == 0 && totalKoli == 0 && totalEcer == 0 &&
        totalKoliHv == 0 && totalEcerHv == 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: Color(0xFF2563EB), size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Data saat ini',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E40AF),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _showInputDetailDialog,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Detail',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF2563EB)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (awb > 0) _buildInfoChip('$awb AWB', Color(0xFFEDE9FE), Color(0xFF6D28D9)),
              if (totalKoli > 0) _buildInfoChip('$totalKoli Koli', Color(0xFFDBEAFE), Color(0xFF1E40AF)),
              if (totalEcer > 0) _buildInfoChip('$totalEcer Ecer', Color(0xFFFEF9C3), Color(0xFF854D0E)),
              if (totalKoliHv > 0) _buildInfoChip('$totalKoliHv Koli HV', Color(0xFFFEF3C7), Color(0xFFB45309)),
              if (totalEcerHv > 0) _buildInfoChip('$totalEcerHv Ecer HV', Color(0xFFFFE7E7), Color(0xFFC2410C)),
            ],
          ),
          const SizedBox(height: 6),
          allZero
              ? const Text(
                  'Semua muatan sudah diangkut di rit ini',
                  style: TextStyle(fontSize: 12, color: Color(0xFF16A34A), fontWeight: FontWeight.w700),
                )
              : Text(
                  'Input baru akan ditambahkan ke data di atas',
                  style: TextStyle(fontSize: 11, color: Colors.blue[600], fontStyle: FontStyle.italic),
                ),
        ],
      ),
    );
  }

  /// Pop-up rincian data saat ini: pecahan sisa per wilayah (JKT/SEG/BTN)
  /// tiap kategori. Read-only — ubah data tetap lewat form input.
  Future<void> _showInputDetailDialog() async {
    final d = _dispValues();
    final rows = <Map<String, dynamic>>[
      {
        'title': 'AWB',
        'total': d['jumlah_awb']!,
        'regions': <int>[],
      },
      {
        'title': 'Koli',
        'total': d['koli_jkt']! + d['koli_seg']! + d['koli_btn']!,
        'regions': [d['koli_jkt']!, d['koli_seg']!, d['koli_btn']!],
      },
      {
        'title': 'Eceran',
        'total': d['ecer_jkt']! + d['ecer_seg']! + d['ecer_btn']!,
        'regions': [d['ecer_jkt']!, d['ecer_seg']!, d['ecer_btn']!],
      },
      {
        'title': 'Koli HV',
        'total': d['koli_hv_jkt']! + d['koli_hv_seg']! + d['koli_hv_btn']!,
        'regions': [d['koli_hv_jkt']!, d['koli_hv_seg']!, d['koli_hv_btn']!],
      },
      {
        'title': 'Ecer HV',
        'total': d['ecer_hv_jkt']! + d['ecer_hv_seg']! + d['ecer_hv_btn']!,
        'regions': [d['ecer_hv_jkt']!, d['ecer_hv_seg']!, d['ecer_hv_btn']!],
      },
    ];
    final hasData = rows.any((row) => (row['total'] as int) > 0);
    const regionLabels = ['JKT', 'SEG', 'BTN'];

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Rincian Data Saat Ini',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            if (_sellerName.isNotEmpty)
              Text(
                '$_sellerName • Rit $_ritaseKe',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
              ),
          ],
        ),
        content: SingleChildScrollView(
          child: hasData
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
              for (final row in rows)
                if ((row['total'] as int) > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              row['title'] as String,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                            ),
                            Text(
                              '${row['total']}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
                            ),
                          ],
                        ),
                        if ((row['regions'] as List<int>).isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              for (var i = 0; i < 3; i++)
                                Expanded(
                                  child: Container(
                                    margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          regionLabels[i],
                                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                        ),
                                        Text(
                                          '${(row['regions'] as List<int>)[i]}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: (row['regions'] as List<int>)[i] > 0
                                                ? const Color(0xFF0F172A)
                                                : const Color(0xFFCBD5E1),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
            ],
          )
              : const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Semua muatan sudah diangkut di rit ini',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Color(0xFF16A34A), fontWeight: FontWeight.w700),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String label, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowInputs(List<_FieldDef> fields) {
    return Row(
      children: [
        for (int i = 0; i < fields.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _buildCompactInput(
              controller: fields[i].controller,
              label: fields[i].label,
              color: fields[i].color,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCompactInput({
    required TextEditingController controller,
    required String label,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 4),
          child: Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '0',
                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  ),
                ),
              ),
              _buildQuickAddButton(controller, 10, color),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '0',
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildQuickAddButton(controller, 10, color),
                  _buildQuickAddButton(controller, 100, color),
                  _buildQuickAddButton(controller, 1000, color),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFotoSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.camera_alt_outlined, size: 20, color: Color(0xFF64748B)),
              SizedBox(width: 8),
              Text(
                'Foto Barang',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_fotoPath != null)
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 32),
                    const SizedBox(height: 8),
                    const Text(
                      'Foto sudah diambil',
                      style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w500),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _fotoPath = null),
                      child: const Text('Hapus'),
                    ),
                  ],
                ),
              ),
            )
          else
            GestureDetector(
              onTap: _pickFoto,
              child: Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFCBD5E1),
                    width: 1.5,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt_outlined, color: Color(0xFF94A3B8), size: 36),
                    SizedBox(height: 8),
                    Text(
                      'Tap untuk ambil foto',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickAddButton(TextEditingController controller, int amount, Color color) {
    return InkWell(
      onTap: () {
        final current = int.tryParse(controller.text) ?? 0;
        controller.text = (current + amount).toString();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '+$amount',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor),
      ),
    );
  }
}

class _FieldDef {
  final TextEditingController controller;
  final String label;
  final Color color;
  _FieldDef(this.controller, this.label, this.color);
}
