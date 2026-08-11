import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/background_tracking.dart';
import 'login_screen.dart';

// Model data dummy Seller
class SellerDummy {
  final String id;
  final String name;
  final String address;
  final String phone;
  final int estimatedAwb;
  final int totalKoli;
  final String jenisStop;

  const SellerDummy({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.estimatedAwb,
    required this.totalKoli,
    this.jenisStop = 'seller',
  });
}

// Model data Riwayat Stop yang Sudah Selesai
class CompletedStop {
  final SellerDummy seller;
  final int actualAwb;
  final int actualKoli;
  final int actualEcer;
  final int totalDurationSeconds;
  final Map<TripStage, int> stageDurations;

  CompletedStop({
    required this.seller,
    required this.actualAwb,
    required this.actualKoli,
    required this.actualEcer,
    required this.totalDurationSeconds,
    required this.stageDurations,
  });
}

// Helper class untuk step timeline dinamis
class _TimelineStep {
  final String title;
  final String subtitle;
  final IconData icon;
  final int segIndex;   // indeks segmen (0 = segmen pertama)
  final int stageIndex; // 0=loading,1=leaving,2=enRoute,3=arrived,-1=completed

  const _TimelineStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.segIndex,
    required this.stageIndex,
  });
}

// Tahapan Status Perjalanan
enum TripStage {
  loadingGoods(
    'Bongkar Muat Barang',
    'Mengisi jumlah koli di [Nama Seller]',
    Icons.inventory_2_outlined,
  ),
  leavingWarehouse(
    'Keluar Gudang',
    'Truk bergerak meninggalkan area [Nama Seller]',
    Icons.local_shipping_outlined,
  ),
  enRoute(
    'Menuju Seller',
    'Sedang dalam perjalanan menuju lokasi tujuan',
    Icons.navigation_outlined,
  ),
  arrived(
    'Tiba di Seller',
    'Truk telah sampai di titik lokasi tujuan',
    Icons.location_on_outlined,
  ),
  completed(
    'Selesai',
    'Seluruh rangkaian penjemputan selesai',
    Icons.check_circle_outline,
  );

  final String title;
  final String subtitle;
  final IconData icon;
  const TripStage(this.title, this.subtitle, this.icon);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SellerDummy> _allSellers = [];
  bool _isLoadingActiveRitase = false;
  bool _isLastRitase = false;

  String _getJenisLokasi(String? jenisStop) {
    if (jenisStop == 'gudang') return 'Gudang';
    if (jenisStop == 'drop_point') return 'Gateway';
    return 'Seller';
  }

  String get _currentDestinationType {
    return _getJenisLokasi(_currentSeller?.jenisStop);
  }

  String get _previousLocationType {
    if (_completedStops.isNotEmpty) {
      return _getJenisLokasi(_completedStops.last.seller.jenisStop);
    }
    return 'Gudang';
  }

  String? _activeRitaseKode;
  String? _activeRitaseStatus;
  List<dynamic> _vehicles = [];
  String? _selectedVehiclePlat;

  // State Perjalanan Multi-Stop
  bool _isTripStarted = false;
  bool _isEntireRouteCompleted = false;
  SellerDummy? _currentSeller;
  TripStage _currentStage = TripStage.loadingGoods;

  final List<CompletedStop> _completedStops = [];

  // Controllers & State untuk Input AWB & Koli saat Bongkar Muat (Dimulai dari 0)
  final TextEditingController _awbInputController = TextEditingController(
    text: '0',
  );
  final TextEditingController _koliInputController = TextEditingController(
    text: '0',
  );
  final TextEditingController _ecerInputController = TextEditingController(
    text: '0',
  );

  int _currentActualAwb = 0;
  int _currentActualKoli = 0;
  int _currentActualEcer = 0;

  // Timer & Real-time Location Tracking State
  Timer? _stopwatchTimer;
  int _activeStageSeconds = 0;
  // ignore: unused_field
  int _totalTripSeconds = 0;
  final Map<TripStage, int> _currentStageDurations = {};

  // Dummy Live GPS Coordinates
  double _latitude = -6.2024;
  double _longitude = 106.6522;
  int _currentSpeedKmH = 0;

  // Identitas tracking (dari konfigurasi, bukan hardcode)
  int _idDriver = 3;
  int _idKendaraan = 2;
  int _idRitase = 4;
  String _driverName = 'AWALUDIN';

  // ── Konstanta Smart GPS Tracking ──
  static const int _gpsRefreshEveryTicks = 8; // baca GPS tiap 8 detik
  static const int _movingSendSeconds = 8; // kirim tiap 8 detik saat bergerak
  static const int _stationarySendSeconds =
      180; // kirim tiap 3 menit saat berhenti
  static const double _speedThresholdKmh = 5; // > 5 km/jam dianggap bergerak
  static const double _moveThresholdDeg =
      0.00005; // geser > ~5 m dianggap bergerak

  // Counter throttling refresh GPS asli
  int _gpsTick = 0;

  // Smart tracking state variables
  double? _lastSentLat;
  double? _lastSentLng;
  DateTime? _lastMovementTime;
  DateTime? _lastSentTime;
  // Titik GPS sebelumnya (untuk fallback hitung kecepatan Haversine)
  DateTime? _prevFixTime;
  double? _prevLat;
  double? _prevLng;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _ensureLocationPermission();
    // Telemetry: catat kapan app dibuka (backend users.last_open).
    ApiClient.markAppOpen();
  }

  Future<void> _loadConfig() async {
    final cfg = await ApiClient.loadDriverConfig();
    if (!mounted) return;
    setState(() {
      _idDriver = cfg['id_driver'] ?? 3;
      _idKendaraan = cfg['id_kendaraan'] ?? 2;
      _idRitase = cfg['id_ritase'] ?? 0;
      _driverName = cfg['driver_name']?.toString() ?? 'AWALUDIN';
    });
    await _fetchVehicles();
    await _fetchActiveRitase();
  }

  Future<void> _fetchVehicles() async {
    final vehicles = await ApiClient.fetchVehicles();
    if (!mounted) return;
    setState(() {
      _vehicles = vehicles;
      try {
        final current = _vehicles.firstWhere(
          (v) => v is Map && v['id'] == _idKendaraan,
        );
        _selectedVehiclePlat = current is Map
            ? current['plat']?.toString()
            : null;
      } catch (_) {}
    });
  }

  Future<void> _fetchActiveRitase() async {
    if (_idKendaraan == 0) return;
    setState(() {
      _isLoadingActiveRitase = true;
      _allSellers.clear();
      _isTripStarted = false;
    });

    final data = await ApiClient.fetchActiveRitase(_idDriver, _idKendaraan);
    if (!mounted) return;

    if (data != null && data['has_active_ritase'] == true) {
      final rawStops = data['stops'];
      final stops = rawStops is List ? rawStops : const <dynamic>[];
      final filteredStops = stops.where((s) {
        // Guard: s harus Map agar pengaksesan indeks String aman
        if (s is! Map) return false;
        return true;
      });
      final parsedSellers = filteredStops.map((item) {
        final m = item as Map;
        return SellerDummy(
          id: (m['id_stop'] ?? '').toString(),
          name: m['nama_lokasi']?.toString() ?? '',
          address: m['alamat']?.toString() ?? '',
          phone: m['no_hp']?.toString() ?? '-',
          estimatedAwb: 20, // Dummy
          totalKoli: 15, // Dummy
          jenisStop: m['jenis_stop']?.toString() ?? 'seller',
        );
      }).toList();

      setState(() {
        _idRitase = data['id_ritase'] ?? 0;
        _activeRitaseKode = data['kode_ritase']?.toString();
        _activeRitaseStatus = data['status']?.toString();
        _isLastRitase = data['is_last_ritase'] == true;
        _allSellers = parsedSellers;
        _isLoadingActiveRitase = false;
      });

      // Save to config
      await ApiClient.saveDriverConfig(
        idDriver: _idDriver,
        idKendaraan: _idKendaraan,
        idRitase: _idRitase,
      );
    } else if (data != null && data['all_completed'] == true) {
      setState(() {
        _idRitase = 0;
        _activeRitaseKode = null;
        _activeRitaseStatus = null;
        _isLoadingActiveRitase = false;
        _isTripStarted = true;
        _isEntireRouteCompleted = true;
      });
    } else {
      setState(() {
        _idRitase = 0;
        _activeRitaseKode = null;
        _activeRitaseStatus = null;
        _isLoadingActiveRitase = false;
      });
    }
  }

  // Minta izin lokasi + ambil posisi pertama
  Future<void> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack('Layanan lokasi HP dimatikan. Aktifkan untuk live tracking.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      _showSnack('Izin lokasi ditolak. Live tracking tidak berjalan.');
      return;
    }
    if (permission == LocationPermission.deniedForever) {
      _showSnack('Izin lokasi ditolak permanen. Atur lewat pengaturan HP.');
      return;
    }
    await _refreshLocation();
  }

  // Ambil posisi GPS asli HP
  Future<void> _refreshLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;

      final now = DateTime.now();

      // Kecepatan utama: dari sensor GPS (m/s -> km/jam)
      final speedMs = pos.speed < 0 ? 0.0 : pos.speed;
      var speedKmh = (speedMs * 3.6).round();

      // Fallback Haversine: kalau sensor tidak memberi kecepatan,
      // hitung jarak antara 2 titik GPS terakhir / selisih waktu.
      if (speedKmh == 0 &&
          _prevLat != null &&
          _prevLng != null &&
          _prevFixTime != null) {
        final dist = Geolocator.distanceBetween(
          _prevLat!,
          _prevLng!,
          pos.latitude,
          pos.longitude,
        );
        final dt = now.difference(_prevFixTime!).inSeconds;
        if (dt > 0) {
          speedKmh = ((dist / dt) * 3.6).round();
        }
      }

      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _currentSpeedKmH = speedKmh;
      });

      // Simpan titik ini sebagai referensi untuk hitungan berikutnya
      _prevLat = pos.latitude;
      _prevLng = pos.longitude;
      _prevFixTime = now;
    } catch (_) {
      // Pertahankan koordinat terakhir jika GPS belum siap
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _stopwatchTimer?.cancel();
    _awbInputController.dispose();
    _koliInputController.dispose();
    _ecerInputController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _stopwatchTimer?.cancel();
    _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_isTripStarted && !_isEntireRouteCompleted) {
          _activeStageSeconds++;
          _totalTripSeconds++;

          // Refresh posisi GPS asli tiap 8 detik
          _gpsTick++;
          if (_gpsTick % _gpsRefreshEveryTicks == 0) {
            _refreshLocation();
          }

          // Smart GPS Tracking upload logic
          // Berjalan -> kirim tiap 8 detik | Berhenti -> kirim tiap 3 menit
          final now = DateTime.now();
          if (_lastSentTime == null ||
              _lastSentLat == null ||
              _lastSentLng == null) {
            _sendInstantTracking();
          } else {
            final latDiff = (_latitude - _lastSentLat!).abs();
            final lngDiff = (_longitude - _lastSentLng!).abs();
            final moved =
                _currentSpeedKmH > _speedThresholdKmh ||
                (latDiff > _moveThresholdDeg || lngDiff > _moveThresholdDeg);

            if (moved) {
              _lastMovementTime = now;
              final secondsSinceLastSent = now
                  .difference(_lastSentTime!)
                  .inSeconds;
              if (secondsSinceLastSent >= _movingSendSeconds) {
                _sendInstantTracking(speed: _currentSpeedKmH);
              }
            } else {
              // Berhenti: kirim heartbeat tiap 3 menit (hemat baterai)
              final secondsSinceLastSent = now
                  .difference(_lastSentTime!)
                  .inSeconds;
              if (secondsSinceLastSent >= _stationarySendSeconds) {
                _lastSentLat = _latitude;
                _lastSentLng = _longitude;
                _lastSentTime = now;
                ApiClient.sendTrackingData(
                  latitude: _latitude,
                  longitude: _longitude,
                  speed: 0,
                  status: '$_currentStageTitle (Hemat Baterai)',
                  koli: _currentActualKoli,
                  idDriver: _idDriver,
                  idKendaraan: _idKendaraan,
                  idRitase: _idRitase,
                );
              }
            }
          }
        }
      });
    });
  }

  void _stopTimer() {
    _stopwatchTimer?.cancel();
  }

  void _resetSimulation() {
    _stopTimer();
    setState(() {
      _isTripStarted = false;
      _isEntireRouteCompleted = false;
      _currentSeller = null;
      _currentStage = TripStage.loadingGoods;
      _activeStageSeconds = 0;
      _totalTripSeconds = 0;
      _currentStageDurations.clear();
      _completedStops.clear();
      _currentActualAwb = 0;
      _currentActualKoli = 0;
      _currentActualEcer = 0;
      _awbInputController.text = '0';
      _koliInputController.text = '0';
      _ecerInputController.text = '0';
      _latitude = -6.2024;
      _longitude = 106.6522;
      _gpsTick = 0;
    });
    _fetchActiveRitase();
  }

  List<SellerDummy> get _availableSellers {
    final visitedIds = _completedStops.map((stop) => stop.seller.id).toSet();
    return _allSellers
        .where((seller) => !visitedIds.contains(seller.id))
        .toList();
  }

  void _startTripDirectly(SellerDummy seller) {
    setState(() {
      _currentSeller = seller;
      _isTripStarted = true;
      _currentStage = TripStage.loadingGoods;
      _activeStageSeconds = 0;
      _currentStageDurations.clear();

      _currentActualAwb = 0;
      _currentActualKoli = 0;
      _currentActualEcer = 0;
      _awbInputController.text = '0';
      _koliInputController.text = '0';
      _ecerInputController.text = '0';
    });
    _startTimer();
    _sendInstantTracking();
  }

  void _sendInstantTracking({
    int? speed,
    int durasiDetik = 0,
    TripStage? stage,
  }) {
    final now = DateTime.now();
    _lastSentLat = _latitude;
    _lastSentLng = _longitude;
    _lastSentTime = now;
    _lastMovementTime = now;
    ApiClient.sendTrackingData(
      latitude: _latitude,
      longitude: _longitude,
      speed: speed ?? _currentSpeedKmH,
      status: _stageToStatusKey(stage ?? _currentStage),
      koli: _currentActualKoli,
      ecer: _currentActualEcer,
      durasiDetik: durasiDetik,
      idDriver: _idDriver,
      idKendaraan: _idKendaraan,
      idRitase: _idRitase,
    );
  }

  // Mapping stage UI -> status backend (ritase_event)
  String _stageToStatusKey(TripStage stage) {
    switch (stage) {
      case TripStage.loadingGoods:
        return 'mulai_loading';
      case TripStage.leavingWarehouse:
        return 'berangkat_gudang';
      case TripStage.enRoute:
        return 'menuju_seller';
      case TripStage.arrived:
        return 'sampai_gudang';
      case TripStage.completed:
        return 'selesai';
    }
  }

  String get _currentStageTitle {
    final currLoc = _currentDestinationType;
    final prevLoc = _previousLocationType;

    switch (_currentStage) {
      case TripStage.loadingGoods:
        return 'Bongkar Muat Barang';
      case TripStage.leavingWarehouse:
        return 'Keluar $prevLoc';
      case TripStage.enRoute:
        return 'Menuju ${_currentSeller?.name ?? currLoc}';
      case TripStage.arrived:
        return 'Tiba di ${_currentSeller?.name ?? currLoc}';
      case TripStage.completed:
        return 'Selesai';
    }
  }

  // ignore: unused_element
  void _showSellerSelectionSheet() {
    final available = _availableSellers;
    if (available.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        SellerDummy? tempSelected = available.first;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _startTripDirectly(tempSelected);
                    },
                    child: const Text('Lanjut'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showVehicleSelection() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pilih Kendaraan Anda',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (_vehicles.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Tidak ada kendaraan tersedia.'),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: _vehicles.length,
                    itemBuilder: (context, index) {
                      final v = _vehicles[index];
                      // Guard: elemen harus Map agar aman diindeks String
                      if (v is! Map) {
                        return const ListTile(title: Text('-'));
                      }
                      final isSelected = _idKendaraan == v['id'];
                      return ListTile(
                        leading: Icon(
                          Icons.local_shipping,
                          color: isSelected ? Colors.blue : Colors.grey,
                        ),
                        title: Text(v['plat']?.toString() ?? '-'),
                        subtitle: Text('${v['type']} - ${v['capacity_kg']}kg'),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: Colors.blue)
                            : null,
                        onTap: () async {
                          Navigator.pop(ctx);
                          setState(() {
                            _idKendaraan = _toInt(v['id']);
                            _selectedVehiclePlat = v['plat']?.toString();
                          });
                          await ApiClient.saveDriverConfig(
                            idDriver: _idDriver,
                            idKendaraan: _idKendaraan,
                            idRitase: 0,
                          );
                          await _fetchActiveRitase();
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.logout_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text(
                'Konfirmasi Logout',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text('Apakah Anda yakin ingin keluar dari akun ini?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text(
                'Batal',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Keluar',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      await AuthService.logout();
      // Matikan background tracking + bersihkan session online di backend.
      try {
        await stopBackgroundTracking();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _confirmAndNextStage() {
    // Validasi inputKoli <= 0 dihapus agar input menjadi opsional

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.help_outline_rounded,
                color: Color(0xFFFF8F00),
                size: 26,
              ),
              SizedBox(width: 8),
              Text(
                'Konfirmasi Status',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text.rich(
            TextSpan(
              text: 'Apakah Anda yakin ingin memperbarui status ke:\n\n',
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              children: [
                TextSpan(
                  text: _getNextStageButtonLabel(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D47A1),
                  ),
                ),
                const TextSpan(text: '?'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Batal',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _nextStage();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8F00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Ya, Lanjutkan',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void _nextStage() {
    if (_currentStage == TripStage.loadingGoods) {
      final inputKoli =
          int.tryParse(_koliInputController.text.trim()) ?? _currentActualKoli;
      final inputEcer =
          int.tryParse(_ecerInputController.text.trim()) ?? _currentActualEcer;
      _currentActualKoli = inputKoli;
      _currentActualEcer = inputEcer;
    }

    // Catat stage yang sedang berakhir (untuk riwayat status backend)
    final finishedStage = _currentStage;
    final finishedDuration =
        _currentStageDurations[finishedStage] ?? _activeStageSeconds;

    setState(() {
      _currentStageDurations[_currentStage] = _activeStageSeconds;
      _activeStageSeconds = 0;

      switch (_currentStage) {
        case TripStage.loadingGoods:
          _currentStage = TripStage.leavingWarehouse;
          break;
        case TripStage.leavingWarehouse:
          _currentStage = TripStage.enRoute;
          break;
        case TripStage.enRoute:
          _currentStage = TripStage.arrived;
          break;
        case TripStage.arrived:
          // Catat segmen ini ke completedStops (yang di-save adalah ORIGIN stop, bukan destination)
          if (_currentSeller != null) {
            final stopTotalDuration = _currentStageDurations.values.fold(
              0,
              (sum, dur) => sum + dur,
            );
            _completedStops.add(
              CompletedStop(
                seller: _currentSeller!,
                actualAwb: _currentActualAwb,
                actualKoli: _currentActualKoli,
                actualEcer: _currentActualEcer,
                totalDurationSeconds: stopTotalDuration,
                stageDurations: Map.from(_currentStageDurations),
              ),
            );
          }

          // Cek apakah ada segmen berikutnya:
          // _currentSeller saat ini adalah ORIGIN dari segmen (allSellers[i])
          // Tujuan dari segmen ini adalah allSellers[i+1]
          // Ada segmen berikutnya hanya jika allSellers[i+2] ada (ada origin berikutnya)
          // Yaitu: _completedStops.length < allSellers.length - 1
          final nextOriginIndex = _completedStops.length; // index SETELAH add
          if (nextOriginIndex < _allSellers.length - 1) {
            // Masih ada origin berikutnya → pindah ke segmen/origin berikutnya
            _currentSeller = _allSellers[nextOriginIndex];
            _currentStage = TripStage.loadingGoods;
            _currentStageDurations.clear();
            _currentActualAwb = 0;
            _currentActualKoli = 0;
            _currentActualEcer = 0;
            _awbInputController.text = '0';
            _koliInputController.text = '0';
            _ecerInputController.text = '0';
          } else {
            // Sudah tiba di tujuan akhir → ritase selesai
            _currentStage = TripStage.completed;
          }
          break;
        case TripStage.completed:
          break;
      }
    });

    // Simpan riwayat status + durasi ke backend (ritase_event)
    ApiClient.sendStatusUpdate(
      idRitase: _idRitase,
      status: _stageToStatusKey(finishedStage),
      latitude: _latitude,
      longitude: _longitude,
      koli: _currentActualKoli,
      ecer: _currentActualEcer,
      durasiDetik: finishedDuration,
    );

    _sendInstantTracking(durasiDetik: finishedDuration, stage: finishedStage);
  }

  Future<void> _finishEntireRoute() async {
    final wasLast = _isLastRitase;
    _stopTimer();
    setState(() {
      _isLoadingActiveRitase = true;
    });

    // Call backend to finish Ritase
    final success = await ApiClient.finishRitase(_idRitase);
    if (!success) {
      _showSnack('Gagal menyelesaikan ritase di server');
      setState(() {
        _isLoadingActiveRitase = false;
      });
      return;
    }

    // Reset current trip state
    setState(() {
      _isTripStarted = false;
      _completedStops.clear();
      _currentStage = TripStage.loadingGoods;
      _activeStageSeconds = 0;
      _currentStageDurations.clear();
    });

    // Fetch next ritase
    await _fetchActiveRitase();

    if (_idRitase != 0 && !wasLast) {
      _showSnack('Berhasil lanjut ke rute berikutnya!');
      setState(() {
        _isTripStarted = true;
        _currentStage = TripStage.loadingGoods;
        _activeStageSeconds = 0;
        _currentStageDurations.clear();
      });
      _startTimer();
      _sendInstantTracking();
    } else {
      setState(() {
        _isEntireRouteCompleted = true;
      });
      _showSnack('Seluruh jadwal hari ini telah selesai!');
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    final minutesStr = minutes.toString().padLeft(2, '0');
    final secondsStr = remainingSeconds.toString().padLeft(2, '0');
    return '$minutesStr:$secondsStr';
  }

  String _formatReadableDuration(int seconds) {
    if (seconds < 60) return '$seconds dtk';
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (remainingSeconds == 0) return '$minutes mnt';
    return '$minutes mnt $remainingSeconds dtk';
  }

  Future<void> _startFreeTrip() async {
    setState(() {
      _isLoadingActiveRitase = true;
    });
    final res = await ApiClient.startFreeTrip(_idDriver, _idKendaraan);
    if (res != null) {
      await _fetchActiveRitase();
      setState(() {
        _isTripStarted = true;
      });
      _startTimer();
      _sendInstantTracking();
    } else {
      setState(() {
        _isLoadingActiveRitase = false;
      });
      _showSnack('Gagal memulai perjalanan bebas');
    }
  }

  Future<void> _showAddStopModal() async {
    final rawSellers = await ApiClient.fetchSellers();
    if (rawSellers.isEmpty) {
      _showSnack('Tidak ada data seller tersedia');
      return;
    }

    final Map<int, Map<String, dynamic>> uniqueSellers = {};
    for (var s in rawSellers) {
      if (s is Map) {
        final id = int.tryParse(s['id_seller']?.toString() ?? '');
        final name =
            (s['nama_seller'] ?? s['name'] ?? s['nama'] ?? 'Seller #$id')
                .toString();
        if (id != null) {
          uniqueSellers[id] = {'id_seller': id, 'nama_seller': name};
        }
      }
    }

    final sellers = uniqueSellers.values.toList();
    if (sellers.isEmpty) {
      _showSnack('Tidak ada data seller valid');
      return;
    }

    int? selectedSellerId = sellers.first['id_seller'] as int?;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Tambah Lokasi',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Pilih Seller',
                        border: OutlineInputBorder(),
                      ),
                      value: selectedSellerId,
                      items: sellers.map<DropdownMenuItem<int>>((s) {
                        return DropdownMenuItem<int>(
                          value: s['id_seller'] as int,
                          child: Text(s['nama_seller'].toString()),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setSheetState(() {
                          selectedSellerId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      onPressed: () async {
                        if (selectedSellerId == null) return;
                        Navigator.pop(ctx);
                        final res = await ApiClient.addStop(
                          _idRitase,
                          selectedSellerId!,
                        );
                        if (res != null) {
                          await _fetchActiveRitase();
                          setState(() {
                            if (_allSellers.isNotEmpty) {
                              _currentSeller = _allSellers.last;
                            }
                          });
                          _showSnack('Berhasil menambahkan lokasi!');
                        } else {
                          _showSnack('Gagal menambahkan lokasi');
                        }
                      },
                      child: const Text('Tambah ke Rute'),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _handleBackToHome() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.arrow_back, color: Color(0xFF0D47A1), size: 24),
              SizedBox(width: 8),
              Text(
                'Kembali ke Beranda',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            'Apakah Anda yakin ingin keluar dan kembali ke halaman beranda? Perjalanan saat ini akan dihentikan.',
            style: TextStyle(fontSize: 14, color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Batal',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _resetSimulation();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Ya, Kembali',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(_isTripStarted ? 'Perjalanan Driver' : 'Beranda Driver'),
        centerTitle: true,
        leading: _isTripStarted
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Kembali ke Beranda',
                onPressed: _handleBackToHome,
              )
            : null,
        actions: [
          IconButton(
            onPressed: _resetSimulation,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset Simulasi',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'Logout',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchActiveRitase();
        },
        color: const Color(0xFF0D47A1),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sederhana: Hai, AWALUDIN! (Tampil saat di Beranda)
              if (!_isTripStarted) ...[
                Text(
                  'Hai, $_driverName!',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 14),
                _buildVehicleCard(),
                const SizedBox(height: 14),
              ],

            // Banner Gudang Outgoing Utama
            _buildWarehouseCard(),
            const SizedBox(height: 16),

            // Tombol Mulai Perjalanan langsung di bawah Asal Gudang (saat di Beranda)
            if (!_isTripStarted) ...[
              if (_allSellers.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Belum ada penugasan rute harian untuk kendaraan ini.',
                          style: TextStyle(color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (_allSellers.isNotEmpty) {
                        setState(() {
                          _completedStops.clear();
                        });
                        _startTripDirectly(_allSellers.first);
                      }
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 26),
                    label: const Text(
                      'Mulai Perjalanan',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 16),

            // Ringkasan Riwayat Seller yang Sudah Dikunjungi (Jika Ada)
            if (_completedStops.isNotEmpty) ...[
              _buildCompletedStopsHistoryCard(),
              const SizedBox(height: 16),
            ],

            // Tampilan Berdasarkan Status Perjalanan
            if (_isTripStarted) ...[
              if (_isEntireRouteCompleted) ...[
                _buildEntireRouteCompletedCard(),
              ] else ...[
                _buildActiveTripSellerCard(),
                const SizedBox(height: 16),
                _buildTimelineStatusCard(),
              ],
            ],
          ],
        ),
      ),
    ),
  );
  }

  // Card GPS Live Tracking Real-Time dengan Indikator Mode Smart Interval
  Widget _buildGpsTrackingBanner() {
    final isActive = _isTripStarted && !_isEntireRouteCompleted;
    final now = DateTime.now();
    final secondsSinceLastMove = _lastMovementTime != null
        ? now.difference(_lastMovementTime!).inSeconds
        : 0;
    final isBatterySaver =
        isActive &&
        secondsSinceLastMove >= _stationarySendSeconds &&
        (_currentStage == TripStage.loadingGoods ||
            _currentStage == TripStage.arrived);

    final String modeLabel = !isActive
        ? 'Standby'
        : (isBatterySaver ? 'Hemat Baterai (3 mnt)' : 'Real-time (8 dtk)');

    final Color statusColor = !isActive
        ? Colors.grey
        : (isBatterySaver ? const Color(0xFFFF8F00) : Colors.green.shade700);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.satellite_alt_rounded,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'GPS Smart Tracking',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[900],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            modeLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isActive
                          ? (isBatterySaver
                                ? 'Armada diam > 3 mnt. Interval pengiriman 3 mnt (hemat baterai)'
                                : 'Armada bergerak. Mengirim koordinat setiap 8 dtk')
                          : 'GPS dalam posisi siaga. Tekan Mulai Perjalanan.',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isActive) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.my_location,
                      size: 14,
                      color: Color(0xFF0D47A1),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_latitude.toStringAsFixed(6)}, ${_longitude.toStringAsFixed(6)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.speed, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '$_currentSpeedKmH km/h (${_currentSpeedKmH > 0 ? 'Berjalan' : 'Berdiam'})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // Kotak Informasi Kendaraan yang dikendarai (Dapat diklik untuk memilih/mengganti kendaraan)
  Widget _buildVehicleCard() {
    Map<String, dynamic>? currentVehicle;
    try {
      currentVehicle =
          _vehicles.firstWhere((v) => v['id'] == _idKendaraan)
              as Map<String, dynamic>?;
    } catch (_) {}

    final plat =
        currentVehicle?['plat']?.toString() ??
        _selectedVehiclePlat ??
        'B 9806 UXV';
    final type = currentVehicle?['type']?.toString() ?? 'CDDL';
    final capacity = currentVehicle?['capacity_kg'] != null
        ? '${currentVehicle!['capacity_kg']} kg'
        : '7.000 kg (7 Ton)';

    return InkWell(
      onTap: _showVehicleSelection,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF0D47A1).withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.local_shipping_outlined,
                      color: Color(0xFF0D47A1),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Kendaraan Operasional',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D47A1).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Text(
                        'Pilih / Ganti',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0D47A1),
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: Color(0xFF0D47A1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      plat,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.yellow,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Jenis: $type',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Kapasitas: $capacity',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Card Informasi Gudang Outgoing
  Widget _buildWarehouseCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D47A1).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.warehouse_outlined,
              color: Color(0xFF0D47A1),
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Asal Gudang',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Gudang Outgoing Utama',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF0D47A1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Card Ringkasan Riwayat Seller yang Sudah Dikunjungi
  Widget _buildCompletedStopsHistoryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade400, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Text(
                'Riwayat Penjemputan Selesai (${_completedStops.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._completedStops.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final stop = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$idx',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop.seller.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          '${stop.actualAwb} AWB, ${stop.actualKoli} Koli, ${stop.actualEcer} Ecer • Durasi: ${_formatReadableDuration(stop.totalDurationSeconds)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.done_all, color: Colors.green, size: 18),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // Card Informasi Seller yang Sedang Dituju
  Widget _buildActiveTripSellerCard() {
    final seller = _currentSeller;
    if (seller == null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300, width: 1.2),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_off_outlined, color: Colors.grey),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Lokasi Seller (Belum Dipilih)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _showAddStopModal,
              icon: const Icon(Icons.add_location_alt, size: 16),
              label: const Text('Pilih Seller', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      );
    }

    String badgeText = 'LOKASI TUJUAN #${_completedStops.length + 1}';
    String labelName = 'Nama Lokasi : ';

    final currentStopNum = _completedStops.length + 1;
    final totalStops = _allSellers.length;

    if (seller.jenisStop == 'gudang') {
      badgeText = 'GUDANG — STOP $currentStopNum dari $totalStops';
      labelName = 'Nama Gudang : ';
    } else if (seller.jenisStop == 'drop_point') {
      badgeText = 'GATEWAY — STOP $currentStopNum dari $totalStops';
      labelName = 'Nama Gateway : ';
    } else if (seller.jenisStop == 'seller') {
      badgeText = 'SELLER — STOP $currentStopNum dari $totalStops';
      labelName = 'Nama Seller : ';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D47A1).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0D47A1), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8F00),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar visual semua stop
          Row(
            children: List.generate(totalStops, (i) {
              final isDone = i < _completedStops.length;
              final isCurrent = i == _completedStops.length;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 6,
                  decoration: BoxDecoration(
                    color: isDone
                        ? Colors.green
                        : isCurrent
                            ? const Color(0xFFFF8F00)
                            : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Text(
            'Progres: ${_completedStops.length} / $totalStops stop selesai',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              children: [
                TextSpan(
                  text: labelName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D47A1),
                  ),
                ),
                TextSpan(
                  text: seller.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[800],
                height: 1.3,
              ),
              children: [
                const TextSpan(
                  text: 'Alamat : ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                TextSpan(text: seller.address),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Timeline Status Perjalanan + Form Input Driver-Friendly di Bagian Bawah
  Widget _buildTimelineStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Status Perjalanan (Live Track)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0D47A1),
                ),
              ),
              if (_currentStage != TripStage.completed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D47A1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.hourglass_top,
                        size: 14,
                        color: Color(0xFF0D47A1),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(_activeStageSeconds),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Color(0xFF0D47A1),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Render Full Expanded Timeline ─────────────────────────────────
          // Bangun flat list semua step untuk seluruh segmen ritase
          // Setiap segmen i: origin = allSellers[i], tujuan = allSellers[i+1]
          // Steps: [Bongkar Muat di origin, Keluar origin, Menuju tujuan, Tiba di tujuan]
          // Ditambah step "Selesai" di akhir
          Builder(builder: (context) {
            // Bangun daftar virtual step
            final segmentCount = (_allSellers.length - 1).clamp(1, 99);
            final List<_TimelineStep> steps = [];

            for (int seg = 0; seg < segmentCount; seg++) {
              final origin = _allSellers[seg];
              final destination = _allSellers[seg + 1];

              final originType = _getJenisLokasi(origin.jenisStop);
              final destType = _getJenisLokasi(destination.jenisStop);

              steps.add(_TimelineStep(
                title: 'Bongkar Muat di ${origin.name}',
                subtitle: 'Proses pengisian muatan di $originType',
                icon: Icons.inventory_2_outlined,
                segIndex: seg,
                stageIndex: 0, // loadingGoods
              ));
              steps.add(_TimelineStep(
                title: 'Keluar dari ${origin.name}',
                subtitle: 'Truk bergerak meninggalkan area $originType',
                icon: Icons.local_shipping_outlined,
                segIndex: seg,
                stageIndex: 1, // leavingWarehouse
              ));
              steps.add(_TimelineStep(
                title: 'Menuju ${destination.name}',
                subtitle: 'Sedang dalam perjalanan menuju $destType tujuan',
                icon: Icons.navigation_outlined,
                segIndex: seg,
                stageIndex: 2, // enRoute
              ));
              steps.add(_TimelineStep(
                title: 'Tiba di ${destination.name}',
                subtitle: 'Truk telah sampai di $destType',
                icon: Icons.location_on_outlined,
                segIndex: seg,
                stageIndex: 3, // arrived
              ));
            }

            // Step terakhir: Selesai
            steps.add(_TimelineStep(
              title: 'Selesai',
              subtitle: 'Seluruh rangkaian perjalanan ritase ini selesai',
              icon: Icons.check_circle_outline,
              segIndex: segmentCount,
              stageIndex: -1, // completed
            ));

            // Hitung global step index saat ini
            // Setiap segmen punya 4 steps (index 0-3)
            // Global current step = completedStops.length * 4 + currentStage.index
            final int currentGlobal;
            if (_currentStage == TripStage.completed) {
              currentGlobal = steps.length - 1; // step "Selesai"
            } else {
              currentGlobal = _completedStops.length * 4 + _currentStage.index;
            }

            return Column(
              children: steps.asMap().entries.map((entry) {
                final globalIdx = entry.key;
                final step = entry.value;
                final isCurrent = globalIdx == currentGlobal;
                final isPassed = globalIdx < currentGlobal;
                final isLast = globalIdx == steps.length - 1;

                // Ambil durasi dari stage jika sudah selesai (hanya untuk segmen aktif)
                int? durationSec;
                if (isPassed && step.segIndex == _completedStops.length && step.stageIndex >= 0) {
                  durationSec = _currentStageDurations[TripStage.values[step.stageIndex]];
                } else if (isPassed && step.segIndex < _completedStops.length && step.stageIndex >= 0) {
                  durationSec = _completedStops[step.segIndex].stageDurations[TripStage.values[step.stageIndex]];
                }

                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isPassed
                                  ? Colors.green
                                  : isCurrent
                                  ? const Color(0xFF0D47A1)
                                  : Colors.grey.shade200,
                              border: Border.all(
                                color: isCurrent
                                    ? const Color(0xFFFF8F00)
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              isPassed ? Icons.check : step.icon,
                              color: (isPassed || isCurrent)
                                  ? Colors.white
                                  : Colors.grey,
                              size: 16,
                            ),
                          ),
                          if (!isLast)
                            Expanded(
                              child: Container(
                                width: 2,
                                color: isPassed
                                    ? Colors.green
                                    : Colors.grey.shade300,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      step.title,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isCurrent
                                            ? FontWeight.bold
                                            : FontWeight.w600,
                                        color: isPassed
                                            ? Colors.green[800]
                                            : isCurrent
                                            ? const Color(0xFF0D47A1)
                                            : Colors.grey[700],
                                      ),
                                    ),
                                  ),
                                  if (durationSec != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green[50],
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.timer,
                                            size: 11,
                                            color: Colors.green,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            _formatReadableDuration(durationSec),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                step.subtitle,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isCurrent
                                      ? Colors.black87
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          }),

          // Form Input Driver-Friendly di Bagian Bawah (saat tahap Bongkar Muat)
          if (_currentStage == TripStage.loadingGoods) ...[
            _buildDriverFriendlyInputForm(),
            const SizedBox(height: 16),
          ],

          const SizedBox(height: 12),

          // Tombol Update Status Berikutnya
          if (_currentStage != TripStage.completed) ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _confirmAndNextStage,
                icon: const Icon(Icons.navigation_outlined, size: 22),
                label: Text(
                  _getNextStageButtonLabel(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8F00),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ),
          ] else ...[
            // Semua stop dalam ritase ini sudah selesai otomatis
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade400),
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 28),
                  const SizedBox(height: 6),
                  Text(
                    'Semua ${_completedStops.length} titik stop dalam ritase ini selesai!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            ElevatedButton.icon(
              onPressed: _finishEntireRoute,
              icon: Icon(
                _isLastRitase
                    ? Icons.check_circle_outline
                    : Icons.arrow_forward,
              ),
              label: Text(
                _isLastRitase
                    ? 'Perjalanan Sudah Selesai'
                    : 'Selesaikan Ritase & Lanjut Rute Berikutnya',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isLastRitase
                    ? Colors.green.shade700
                    : const Color(0xFF0D47A1),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Form Input Driver-Friendly di Bagian Bawah (Tombol +, - dan Font Besar)
  Widget _buildDriverFriendlyInputForm() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFF8F00).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF8F00), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8F00),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.touch_app,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Input Realisasi Muatan Barang',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'Masukkan jumlah Koli yang diangkut',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildVerticalStepperControl(
            label: 'Jumlah Koli (Box/Paket)',
            controller: _koliInputController,
            icon: Icons.inventory_2,
            color: const Color(0xFFFF8F00),
          ),
          const SizedBox(height: 12),
          _buildVerticalStepperControl(
            label: 'Jumlah Ecer (Pcs)',
            controller: _ecerInputController,
            icon: Icons.widgets_outlined,
            color: const Color(0xFF1E88E5),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalStepperControl({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Material(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {
                    int val = int.tryParse(controller.text.trim()) ?? 0;
                    if (val > 0) {
                      setState(() {
                        controller.text = (val - 1).toString();
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.remove,
                      color: Colors.red,
                      size: 28,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Material(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {
                    int val = int.tryParse(controller.text.trim()) ?? 0;
                    setState(() {
                      controller.text = (val + 1).toString();
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.green.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add, color: Colors.green, size: 28),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Tombol Tambah Cepat (+10, +100, +1000) & Reset
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildQuickAddChip(
                  controller: controller,
                  amount: 10,
                  label: '+10',
                ),
                const SizedBox(width: 8),
                _buildQuickAddChip(
                  controller: controller,
                  amount: 100,
                  label: '+100',
                ),
                const SizedBox(width: 8),
                _buildQuickAddChip(
                  controller: controller,
                  amount: 1000,
                  label: '+1000',
                ),
                const SizedBox(width: 8),
                _buildResetChip(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAddChip({
    required TextEditingController controller,
    required int amount,
    required String label,
  }) {
    return Material(
      color: const Color(0xFFFF8F00).withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          int val = int.tryParse(controller.text.trim()) ?? 0;
          setState(() {
            controller.text = (val + amount).toString();
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(0xFFFF8F00).withValues(alpha: 0.5),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFFD84315),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResetChip({required TextEditingController controller}) {
    return Material(
      color: Colors.grey[100],
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          setState(() {
            controller.text = '0';
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.refresh, size: 14, color: Colors.grey[700]),
              const SizedBox(width: 4),
              Text(
                'Reset',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getNextStageButtonLabel() {
    final prevLoc = _previousLocationType;
    final currLoc = _currentDestinationType;

    switch (_currentStage) {
      case TripStage.loadingGoods:
        return 'Selesai Muat -> Keluar $prevLoc';
      case TripStage.leavingWarehouse:
        return 'Keluar $prevLoc -> Menuju $currLoc';
      case TripStage.enRoute:
        return 'Tiba di Lokasi $currLoc';
      case TripStage.arrived:
        return 'Selesaikan Penjemputan di $currLoc Ini';
      case TripStage.completed:
        return 'Penjemputan Selesai';
    }
  }

  Widget _buildEntireRouteCompletedCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.shade400, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events, color: Colors.green, size: 56),
          const SizedBox(height: 12),
          const Text(
            'Seluruh Perjalanan Selesai!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Terima kasih untuk pengirimannya hari ini, anda sudah bekerja dengan baik!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () async {
              _stopTimer();
              setState(() {
                _isLoadingActiveRitase = true;
              });
              await ApiClient.resetDriverTestRitase(_idDriver);
              setState(() {
                _isTripStarted = false;
                _isEntireRouteCompleted = false;
                _completedStops.clear();
                _currentStage = TripStage.loadingGoods;
                _activeStageSeconds = 0;
                _currentStageDurations.clear();
              });
              await _fetchActiveRitase();
            },
            icon: const Icon(Icons.replay),
            label: const Text(
              'Mulai Ulang Perjalanan (Testing)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8F00),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _resetSimulation,
            icon: const Icon(Icons.home),
            label: const Text('Kembali ke Beranda Utama'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Konversi aman ke int — tahan null, tipe salah, dan String.
int _toInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}
