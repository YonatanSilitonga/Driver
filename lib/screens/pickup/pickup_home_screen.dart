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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  Timer? _clockTimer;
  Timer? _trackingTimer;
  final ValueNotifier<String> _currentTimeNotifier = ValueNotifier<String>('');

  int _idUser = 0;
  int _idDriver = 39;
  int _idKendaraan = 18;
  String _platNomor = 'B 9278 PDD';
  String _driverName = '';
  String _username = '';
  String _currentStatus = 'standby'; // 'standby' | 'menuju_seller' | 'menuju_gudang' | 'selesai'
  
  bool _isLoading = false;
  bool _hasAutoOpenedForm = false;
  bool _isFormScreenOpen = false;
  Position? _lastSentPosition;
  DateTime? _lastSentTime;
  List<Map<String, dynamic>> _historyLogs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

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

    // Cek posisi GPS setiap 10 detik (dikirim jika pergerakan >= 5 meter atau heartbeat 60s)
    _trackingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _sendLiveLocation();
        ensureTrackingRunning();
      }
    });

    _loadUserData().then((_) {
      if (mounted) {
        _sendLiveLocation(force: true);
        ensureTrackingRunning();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Driver kembali ke aplikasi setelah membuka aplikasi lain (WA, Maps, Kamera, dll.)
      // Jangan panggil _loadUserData() agar tidak memicu auto-open form ganda!
      _refreshHistory();
      if (mounted) {
        _sendLiveLocation(force: true);
        ensureTrackingRunning();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _clockTimer?.cancel();
    _trackingTimer?.cancel();
    _currentTimeNotifier.dispose();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    _currentTimeNotifier.value = '$h.$m.$s';
  }

  Future<void> _loadUserData() async {
    try {
      final cfg = await ApiClient.loadDriverConfig();
      _idUser = cfg['id_user'] as int? ?? 0;
      _idDriver = cfg['id_driver'] as int? ?? 0;
      if (_idDriver <= 0) _idDriver = (_idUser > 0 ? _idUser : 39);
      _idKendaraan = cfg['id_kendaraan'] as int? ?? 0;
      if (_idKendaraan <= 0) _idKendaraan = 18;
      _platNomor = (cfg['plat_nomor'] as String? ?? '').isNotEmpty
          ? cfg['plat_nomor'] as String
          : 'B 9278 PDD';
      _driverName = cfg['driver_name'] as String? ?? '';
      _username = cfg['username'] as String? ?? '';

      // 1. Baca status lokal secara instan (0 delay tanpa menunggu jaringan)
      final localStatus = (cfg['pickup_status'] ?? '').toString();
      if (localStatus.isNotEmpty && localStatus != 'standby') {
        _currentStatus = localStatus;
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }

      // Jika perjalanan sedang aktif menuju seller, langsung buka form input muatan seller
      if (_currentStatus == 'menuju_seller' && !_hasAutoOpenedForm && !_isFormScreenOpen) {
        _hasAutoOpenedForm = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openPickupForm();
          }
        });
      }

      // 2. Sinkronisasi data user & history di background
      if (_idUser == 0 || _driverName.isEmpty || _idDriver <= 0) {
        try {
          final me = await AuthService.me().timeout(const Duration(seconds: 3));
          if (me != null) {
            _idUser = (me['id_user'] is int) ? me['id_user'] : int.tryParse(me['id_user'].toString()) ?? 0;
            final parsedDriver = (me['id_driver'] is int) ? me['id_driver'] : int.tryParse(me['id_driver']?.toString() ?? '0') ?? 0;
            if (parsedDriver > 0) _idDriver = parsedDriver;
            _driverName = (me['nama'] ?? me['name'] ?? me['username'] ?? 'Driver').toString();
            _username = (me['username'] ?? '').toString();
          }
        } catch (_) {}
      }

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
        pickupStatus: _currentStatus,
      );

      await _refreshHistory();
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

  /// Mengambil log yang termasuk dalam perjalanan pickup aktif saat ini (setelah status 'selesai' terakhir).
  List<Map<String, dynamic>> get _currentSessionLogs {
    final activeLogs = <Map<String, dynamic>>[];
    for (final log in _historyLogs) {
      final status = (log['status'] ?? '').toString().toLowerCase();
      if (status == 'selesai') {
        break; // Berhenti di checkpoint 'selesai' terakhir
      }
      activeLogs.add(log);
    }
    return activeLogs;
  }

  /// Jumlah seller riil yang muatannya sudah diinput pada sesi aktif
  int get _currentSessionSellerCount {
    return _currentSessionLogs.where((l) {
      final seller = (l['asal_seller'] ?? '').toString().trim();
      return seller.isNotEmpty &&
          seller != 'Menuju Seller' &&
          seller != 'Perjalanan ke Gudang' &&
          seller != 'Gudang';
    }).length;
  }

  /// Kirim posisi live GPS driver pickup langsung ke endpoint /driver/tracking
  Future<void> _sendLiveLocation({bool force = false}) async {
    final effectiveDriverId = _idDriver > 0 ? _idDriver : (_idUser > 0 ? _idUser : 39);
    final effectiveKendaraanId = _idKendaraan > 0 ? _idKendaraan : 18;
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
          return;
        }
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 7),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) return;

      final now = DateTime.now();
      if (!force && _lastSentPosition != null && _lastSentTime != null) {
        final dist = Geolocator.distanceBetween(
          _lastSentPosition!.latitude,
          _lastSentPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
        final sec = now.difference(_lastSentTime!).inSeconds;
        // Skip jika belum 10 detik ATAU pergerakan < 5m (kecuali sudah >= 55s untuk heartbeat agar armada tidak offline)
        if (sec < 10) return;
        if (dist < 5.0 && sec < 55) return;
      }

      String statusKey = 'Standby';
      if (_currentStatus == 'menuju_seller') {
        statusKey = 'Sedang Menuju';
      } else if (_currentStatus == 'menuju_gudang') {
        statusKey = 'Kembali ke Gudang';
      } else if (_currentStatus == 'selesai') {
        statusKey = 'Selesai';
      }

      // Hitung muatan HANYA dari sesi perjalanan aktif saat ini
      int totalAwb = 0;
      int totalHv = 0;
      for (final log in _currentSessionLogs) {
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
        idDriver: effectiveDriverId,
        idKendaraan: effectiveKendaraanId,
        idRitase: 0,
      );
      _lastSentPosition = pos;
      _lastSentTime = now;
      // ignore: avoid_print
      print('📍 [PICKUP GPS] Posisi live driver pickup masuk armada_tracking: (${pos.latitude}, ${pos.longitude}) | Kendaraan: $effectiveKendaraanId | Driver: $effectiveDriverId | Muatan: $totalAwb AWB');
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ [PICKUP GPS] Gagal kirim lokasi: $e');
    }
  }

  /// Membuka form muatan seller dan menangani perubahan status secara langsung
  Future<void> _openPickupForm() async {
    if (_isFormScreenOpen) return;
    _isFormScreenOpen = true;
    _hasAutoOpenedForm = true;

    if (_idKendaraan <= 0) {
      final selected = await _showSelectVehicleDialog();
      if (!selected || !mounted) {
        _isFormScreenOpen = false;
        return;
      }
    }
    if (!mounted) {
      _isFormScreenOpen = false;
      return;
    }

    final newStatus = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PickupFormScreen(
          idUser: _idUser,
          namaDriver: _driverName.isNotEmpty ? _driverName : _username,
          currentStatus: _currentStatus,
        ),
      ),
    );

    _isFormScreenOpen = false;

    if (newStatus != null && newStatus.isNotEmpty && mounted) {
      setState(() {
        _currentStatus = newStatus;
      });
      await ApiClient.savePickupStatus(newStatus);
    }

    await _refreshHistory();
    if (_currentStatus == 'menuju_seller' || _currentStatus == 'menuju_gudang') {
      await _sendLiveLocation(force: true);
    }
  }

  Future<void> _refreshHistory() async {
    if (_idUser <= 0) return;
    try {
      final now = DateTime.now();
      final y = now.year.toString();
      final m = now.month.toString().padLeft(2, '0');
      final d = now.day.toString().padLeft(2, '0');
      final todayStr = '$y-$m-$d';

      final logs = await PickupService.getPickupHistory(_idUser, tanggal: todayStr);

      // Pastikan hanya data tanggal hari ini yang dimasukkan ke riwayat hari ini
      final todayLogs = logs.where((l) {
        final tgl = (l['tanggal'] ?? '').toString().trim();
        return tgl.isEmpty || tgl == todayStr;
      }).toList();

      String latestStatus = _currentStatus;

      if (todayLogs.isNotEmpty) {
        final serverStatus = (todayLogs.first['status'] ?? '').toString();
        if (serverStatus.isNotEmpty) {
          latestStatus = serverStatus;
        }
      }

      if (mounted) {
        setState(() {
          _historyLogs = todayLogs;
          _currentStatus = latestStatus;
        });
        await ApiClient.savePickupStatus(_currentStatus);
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

      final effectiveDriverId = _idDriver > 0 ? _idDriver : (_idUser > 0 ? _idUser : 39);
      await ApiClient.saveDriverConfig(
        idDriver: effectiveDriverId,
        idKendaraan: id,
        idRitase: 0,
        driverName: _driverName,
        role: 'driver_pickup',
        idUser: _idUser,
        username: _username,
        platNomor: plat,
      );

      await ensureTrackingRunning();
      await _sendLiveLocation(force: true);

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
    } else if (_currentStatus == 'menuju_seller') {
      await _openPickupForm();
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

      // 2. Update status lokal dan riwayat
      if (mounted) {
        setState(() {
          _currentStatus = 'selesai';
        });
      }
      await ApiClient.savePickupStatus('selesai');
      await _sendLiveLocation(force: true);
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
      if (!selected || !mounted) return;
    }

    setState(() {
      _currentStatus = 'menuju_seller';
    });
    await ApiClient.savePickupStatus('menuju_seller');

    // Jalankan sync backend & GPS tracking di background tanpa memblokir pembukaan form
    () async {
      try {
        await PickupService.savePickupBarang(
          idUser: _idUser,
          namaDriver: _driverName.isNotEmpty ? _driverName : _username,
          asalSeller: 'Gudang',
          jumlahBarang: 0,
          highValue: 0,
          koli: 0,
          ecer: 0,
          status: 'menuju_seller',
          catatan: 'Berangkat dari gudang menuju seller',
        );
      } catch (_) {}

      try {
        await _sendLiveLocation(force: true);
      } catch (_) {}

      try {
        await startBackgroundTracking();
      } catch (_) {}

      if (mounted) {
        _refreshHistory();
      }
    }();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Perjalanan dimulai · Sedang menuju seller.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: Color(0xFF0D47A1),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );

    // Langsung buka form input muatan seller secara instan
    if (!mounted) return;
    await _openPickupForm();
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
                        final isSelesai = status == 'selesai';
                        final isMenujuGudang = status == 'menuju_gudang';

                        String statusLabel = 'Menuju Seller';
                        Color statusColor = const Color(0xFFF59E0B);
                        IconData iconData = Icons.store_rounded;
                        Color iconBgColor = const Color(0xFFF27D26);

                        if (isSelesai) {
                          statusLabel = 'Selesai di Gudang';
                          statusColor = const Color(0xFF3B82F6);
                          iconData = Icons.check_circle_rounded;
                          iconBgColor = const Color(0xFF3B82F6);
                        } else if (isMenujuGudang) {
                          statusLabel = 'Menuju Gudang';
                          statusColor = const Color(0xFF10B981);
                          iconData = Icons.warehouse_rounded;
                          iconBgColor = const Color(0xFF10B981);
                        }

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelesai ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelesai ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: iconBgColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  iconData,
                                  color: iconBgColor,
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
                                      statusLabel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: statusColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isSelesai)
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
                // Background peta samar halus (ringan GPU, tanpa Opacity off-screen buffer)
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage('assets/images/map_bg.png'),
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        opacity: 0.04,
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
                            child: Builder(
                              builder: (context) {
                                final isGudangPhase = _currentStatus == 'menuju_gudang';
                                final circleColor = isGudangPhase ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
                                return Container(
                                  width: 250,
                                  height: 250,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: circleColor.withValues(alpha: 0.25),
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 205,
                                      height: 205,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: circleColor,
                                        boxShadow: [
                                          BoxShadow(
                                            color: circleColor.withValues(alpha: 0.3),
                                            blurRadius: 18,
                                            spreadRadius: 2,
                                            offset: const Offset(0, 4),
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
                                      ValueListenableBuilder<String>(
                                        valueListenable: _currentTimeNotifier,
                                        builder: (context, timeStr, _) {
                                          return Text(
                                            timeStr,
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.9),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
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
                              _currentStatus == 'menuju_seller' || _currentStatus == 'menuju_gudang'
                                  ? (_currentSessionSellerCount == 0
                                      ? 'Lihat muatan aktif (0 seller)'
                                      : 'Lihat muatan aktif ($_currentSessionSellerCount seller)')
                                  : (_historyLogs.isEmpty
                                      ? 'Lihat riwayat pickup'
                                      : 'Lihat riwayat pickup (${_historyLogs.length} riwayat)'),
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
