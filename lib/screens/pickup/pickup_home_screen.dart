import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/background_tracking.dart';
import '../../services/pickup_service.dart';
import '../login_screen.dart';
import 'pickup_form_screen.dart';

class PickupHomeScreen extends StatefulWidget {
  const PickupHomeScreen({super.key});

  @override
  State<PickupHomeScreen> createState() => _PickupHomeScreenState();
}

class _PickupHomeScreenState extends State<PickupHomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  Timer? _clockTimer;
  Timer? _trackingTimer;
  String _currentTime = '';

  int _idUser = 0;
  int _idDriver = 39;
  int _idKendaraan = 18;
  String _platNomor = 'B 9278 PDD';
  String _driverName = '';
  String _username = '';
  String _currentStatus = 'standby'; // 'standby' | 'menuju_seller' | 'menuju_gudang' | 'selesai'
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _historyLogs = [];

  @override
  void initState() {
    super.initState();

    // Animasi denyut halus untuk tombol bulat besar
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _updateTime();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateTime();
    });

    // Kirim posisi GPS secara berkala setiap 15 detik HANYA jika pickup sedang aktif
    _trackingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && (_currentStatus == 'menuju_seller' || _currentStatus == 'menuju_gudang')) {
        _sendLiveLocation();
      }
    });

    _loadUserData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _clockTimer?.cancel();
    _trackingTimer?.cancel();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    setState(() {
      _currentTime = '$h.$m.$s';
    });
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      final cfg = await ApiClient.loadDriverConfig();
      _idUser = cfg['id_user'] as int? ?? 0;
      _idDriver = cfg['id_driver'] as int? ?? 39;
      _idKendaraan = cfg['id_kendaraan'] as int? ?? 18;
      _platNomor = (cfg['plat_nomor'] as String? ?? '').isNotEmpty
          ? cfg['plat_nomor'] as String
          : 'B 9278 PDD';
      _driverName = cfg['driver_name'] as String? ?? '';
      _username = cfg['username'] as String? ?? '';

      if (_idUser == 0 || _driverName.isEmpty || _idDriver <= 0) {
        final me = await AuthService.me();
        if (me != null) {
          _idUser = (me['id_user'] is int) ? me['id_user'] : int.tryParse(me['id_user'].toString()) ?? 0;
          final parsedDriver = (me['id_driver'] is int) ? me['id_driver'] : int.tryParse(me['id_driver']?.toString() ?? '0') ?? 0;
          if (parsedDriver > 0) _idDriver = parsedDriver;
          _driverName = (me['nama'] ?? me['name'] ?? me['username'] ?? 'Driver').toString();
          _username = (me['username'] ?? '').toString();
        }
      }

      // Pastikan selalu ada idKendaraan default (18) & idDriver default (39)
      if (_idDriver <= 0) _idDriver = 39;
      if (_idKendaraan <= 0) _idKendaraan = 18;

      await ApiClient.saveDriverConfig(
        idDriver: _idDriver,
        idKendaraan: _idKendaraan,
        idRitase: 0,
        driverName: _driverName.isNotEmpty ? _driverName : 'pickup',
        role: 'driver_pickup',
        idUser: _idUser,
        username: _username.isNotEmpty ? _username : 'pickup',
        platNomor: _platNomor,
      );

      await _refreshHistory();
      // Kirim tracking pertama kali HANYA jika perjalanan sedang aktif
      if (_currentStatus == 'menuju_seller' || _currentStatus == 'menuju_gudang') {
        await _sendLiveLocation();
      }
    } catch (_) {
      // Abaikan error jaringan saat inisialisasi awal
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Kirim posisi live GPS driver pickup langsung ke endpoint /driver/tracking
  Future<void> _sendLiveLocation({bool force = false}) async {
    if (_idDriver <= 0 || _idKendaraan <= 0) return;
    if (!force && _currentStatus != 'menuju_seller' && _currentStatus != 'menuju_gudang') return;
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
          return;
        }
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 6),
      );

      String statusKey = 'Standby';
      if (_currentStatus == 'menuju_seller') {
        statusKey = 'Sedang Menuju';
      } else if (_currentStatus == 'menuju_gudang') {
        statusKey = 'Kembali ke Gudang';
      } else if (_currentStatus == 'selesai') {
        statusKey = 'Selesai';
      }

      int totalAwb = 0;
      int totalHv = 0;
      for (final log in _historyLogs) {
        totalAwb += (log['jumlah_barang'] as int? ?? 0);
        totalHv += (log['high_value'] as int? ?? 0);
      }

      await ApiClient.sendTrackingData(
        latitude: pos.latitude,
        longitude: pos.longitude,
        speed: (pos.speed < 0 ? 0 : pos.speed * 3.6).round(),
        status: statusKey,
        koli: totalAwb,
        highValue: totalHv,
        idDriver: _idDriver,
        idKendaraan: _idKendaraan,
        idRitase: 0,
      );
      // ignore: avoid_print
      print('📍 [PICKUP GPS] Posisi live driver pickup masuk armada_tracking: (${pos.latitude}, ${pos.longitude}) | Kendaraan: $_idKendaraan | Driver: $_idDriver');
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ [PICKUP GPS] Gagal kirim lokasi: $e');
    }
  }

  Future<void> _refreshHistory() async {
    if (_idUser <= 0) return;
    try {
      final logs = await PickupService.getPickupHistory(_idUser);
      String latestStatus = 'standby';

      if (logs.isNotEmpty) {
        latestStatus = (logs.first['status'] ?? 'standby').toString();
      }

      if (mounted) {
        setState(() {
          _historyLogs = logs;
          _currentStatus = latestStatus;
        });
      }
    } catch (_) {}
  }

  Future<bool> _showSelectVehicleDialog() async {
    List<Map<String, dynamic>> vehicles = [];
    bool fetching = true;

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          if (fetching) {
            ApiClient.dio.get('/vehicles').then((res) {
              final body = res.data;
              List<Map<String, dynamic>> list = [];
              if (body is Map && body['data'] is List) {
                list = (body['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
              } else if (body is List) {
                list = body.map((e) => Map<String, dynamic>.from(e as Map)).toList();
              }
              setModalState(() {
                vehicles = list;
                fetching = false;
              });
            }).catchError((_) {
              setModalState(() {
                fetching = false;
              });
            });
          }

          return Container(
            height: MediaQuery.of(ctx).size.height * 0.60,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Pilih Kendaraan Pickup',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: fetching
                      ? const Center(child: CircularProgressIndicator())
                      : vehicles.isEmpty
                          ? const Center(
                              child: Text('Tidak ada kendaraan tersedia', style: TextStyle(color: Color(0xFF94A3B8))),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: vehicles.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final v = vehicles[index];
                                final id = (v['id'] ?? v['id_kendaraan'] ?? 0) as int;
                                final plat = (v['plat'] ?? v['plat_nomor'] ?? '').toString();
                                final type = (v['type'] ?? v['jenis_kendaraan'] ?? 'Kendaraan').toString();
                                final isSelected = id == _idKendaraan;

                                return InkWell(
                                  onTap: () => Navigator.pop(ctx, v),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFFF27D26).withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected ? const Color(0xFFF27D26) : const Color(0xFFE2E8F0),
                                        width: isSelected ? 1.6 : 1.0,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF27D26).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.two_wheeler_rounded, color: Color(0xFFF27D26), size: 22),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                plat,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(type, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                            ],
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(Icons.check_circle_rounded, color: Color(0xFFF27D26), size: 22),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (selected != null) {
      final id = (selected['id'] ?? selected['id_kendaraan'] ?? 0) as int;
      final plat = (selected['plat'] ?? selected['plat_nomor'] ?? '').toString();

      setState(() {
        _idKendaraan = id;
        _platNomor = plat;
      });

      await ApiClient.saveDriverConfig(
        idDriver: _idDriver,
        idKendaraan: id,
        idRitase: 0,
        driverName: _driverName,
        role: 'driver_pickup',
        idUser: _idUser,
        username: _username,
        platNomor: plat,
      );

      await _sendLiveLocation();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kendaraan aktif: $plat'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return true;
    }
    return false;
  }

  Future<void> _handleCircleTap() async {
    if (_currentStatus == 'menuju_gudang') {
      await _handleSampaiGudang();
    } else {
      await _handleStartPickup();
    }
  }

  Future<void> _handleSampaiGudang() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: const Text(
          'Konfirmasi Anda sudah sampai gudang?',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'batal'),
            child: const Text('Batal', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, 'sampai'),
            child: const Text('Ya', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result != 'sampai') return;

    setState(() => _isLoading = true);
    try {
      // 1. Simpan log status selesai di database
      await PickupService.savePickupBarang(
        idUser: _idUser,
        namaDriver: _driverName.isNotEmpty ? _driverName : _username,
        asalSeller: 'Gudang',
        jumlahBarang: 0,
        highValue: 0,
        koli: 0,
        ecer: 0,
        status: 'selesai',
        catatan: 'Perjalanan selesai · Sampai di gudang',
      );

      // 2. Kirim sinyal offline agar langsung terhapus dari armada_tracking dan peta Fadel
      await ApiClient.sendTrackingOffline(
        idKendaraan: _idKendaraan,
        idDriver: _idDriver,
      );

      // 3. Matikan background tracking
      try {
        await stopBackgroundTracking();
      } catch (_) {}

      // 4. Update status lokal dan riwayat
      if (mounted) {
        setState(() {
          _currentStatus = 'selesai';
        });
      }
      await _refreshHistory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perjalanan selesai! Anda telah sampai di gudang.'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyelesaikan perjalanan: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleStartPickup() async {
    // Jika belum memilih kendaraan, minta pilih dulu
    if (_idKendaraan <= 0) {
      final selected = await _showSelectVehicleDialog();
      if (!selected) return;
    }

    // Pastikan GPS tracking terkirim saat memulai pickup
    await _sendLiveLocation(force: true);
    try {
      await startBackgroundTracking();
    } catch (_) {}

    if (!mounted) return;

    // Buka form input muatan seller
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PickupFormScreen(
          idUser: _idUser,
          namaDriver: _driverName.isNotEmpty ? _driverName : _username,
          currentStatus: _currentStatus,
        ),
      ),
    );

    await _refreshHistory();
    if (_currentStatus == 'menuju_seller' || _currentStatus == 'menuju_gudang') {
      await _sendLiveLocation(force: true);
    }
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 10),
            Text('Konfirmasi Logout', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Apakah Anda yakin ingin keluar dari akun Driver Pickup?',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  String _getStatusText() {
    switch (_currentStatus) {
      case 'menuju_seller':
        return 'Sedang menuju seller berikutnya';
      case 'menuju_gudang':
        return 'Sedang perjalanan kembali ke gudang';
      case 'selesai':
        return 'Perjalanan selesai · Sudah sampai di gudang';
      default:
        return 'Belum mulai penjemputan paket';
    }
  }

  void _showHistoryBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.65,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Riwayat Pickup Hari Ini (${_historyLogs.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _historyLogs.isEmpty
                  ? const Center(
                      child: Text(
                        'Belum ada data penjemputan hari ini.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _historyLogs.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final log = _historyLogs[index];
                        final seller = log['asal_seller'] ?? '-';
                        final awb = log['jumlah_barang'] ?? 0;
                        final hv = log['high_value'] ?? 0;
                        final status = log['status'] ?? '';
                        final isMenujuGudang = status == 'menuju_gudang';

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isMenujuGudang
                                      ? const Color(0xFF10B981).withValues(alpha: 0.1)
                                      : const Color(0xFFF27D26).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isMenujuGudang ? Icons.warehouse_rounded : Icons.store_rounded,
                                  color: isMenujuGudang ? const Color(0xFF10B981) : const Color(0xFFF27D26),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      seller.toString().isNotEmpty ? seller.toString() : 'Seller Implan',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      status == 'menuju_gudang' ? 'Menuju Gudang' : 'Menuju Seller',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isMenujuGudang ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '$awb AWB',
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                  ),
                                  if (hv > 0)
                                    Text(
                                      '$hv HV',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehicleLabel = _platNomor.isNotEmpty ? _platNomor : 'PILIH KENDARAAN';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          tooltip: 'Keluar',
          onPressed: _confirmLogout,
        ),
        title: const Text(
          'Pickup',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF0F172A), size: 24),
            tooltip: 'Segarkan data',
            onPressed: () async {
              await _refreshHistory();
              await _sendLiveLocation();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFF1F5F9), height: 1),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Background peta samar halus
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.04,
                    child: Container(
                      decoration: const BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage('assets/images/map_bg.png'),
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          onError: null,
                        ),
                      ),
                    ),
                  ),
                ),

                // Konten utama persis seperti gambar referensi
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Spacer(flex: 3),

                        // TOMBOL BULAT BESAR ALA REFERENSI GAMBAR
                        ScaleTransition(
                          scale: _pulseAnimation,
                          child: GestureDetector(
                            onTap: _handleCircleTap,
                            child: Container(
                              width: 250,
                              height: 250,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                              ),
                              child: Center(
                                child: Container(
                                  width: 205,
                                  height: 205,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFFF59E0B),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0x33F59E0B),
                                        blurRadius: 18,
                                        spreadRadius: 2,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Plat Nomor / Tombol Pilih Kendaraan
                                      InkWell(
                                        onTap: _showSelectVehicleDialog,
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                vehicleLabel,
                                                style: TextStyle(
                                                  color: Colors.white.withValues(alpha: 0.9),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(
                                                Icons.expand_more_rounded,
                                                color: Colors.white.withValues(alpha: 0.8),
                                                size: 16,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _currentStatus == 'menuju_gudang'
                                            ? 'Sudah Sampai\nke Gudang'
                                            : (_currentStatus == 'menuju_seller'
                                                ? 'Input\nMuatan'
                                                : 'Mulai\nPickup'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: _currentStatus == 'menuju_gudang' ? 22 : 25,
                                          fontWeight: FontWeight.w800,
                                          height: 1.15,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _currentTime,
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.9),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 36),

                        // Lokasi / Status jangkauan teks
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.location_on, color: Color(0xFF0F172A), size: 18),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _getStatusText(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Link teks bawah
                        GestureDetector(
                          onTap: _showHistoryBottomSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Text(
                              _historyLogs.isEmpty
                                  ? 'Lihat riwayat pickup'
                                  : 'Lihat riwayat pickup (${_historyLogs.length} seller)',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),

                        const Spacer(flex: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
