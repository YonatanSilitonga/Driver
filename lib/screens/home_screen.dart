import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/background_tracking.dart';
import 'login_screen.dart';
import 'permission_guide_screen.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_dialog.dart';
import '../widgets/vehicle_card.dart';
import '../widgets/origin_card.dart';

// ── Models (unchanged) ──

class SellerDummy {
  final String id;
  final String name;
  final String address;
  final String phone;
  final int estimatedAwb;
  final int totalKoli;
  final String jenisStop;
  final double? latitude;
  final double? longitude;

  const SellerDummy({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.estimatedAwb,
    required this.totalKoli,
    this.jenisStop = 'seller',
    this.latitude,
    this.longitude,
  });
}

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

class _TimelineStep {
  final String title;
  final String subtitle;
  final IconData icon;
  final int segIndex;
  final int stageIndex;

  const _TimelineStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.segIndex,
    required this.stageIndex,
  });
}

enum TripStage {
  loadingGoods(
    'Bongkar Muat Barang',
    'Mengisi jumlah koli di [Nama Seller]',
    Icons.inventory_2_outlined,
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

// ── State ──

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<SellerDummy> _allSellers = [];
  bool _isLastRitase = false;

  String _getJenisLokasi(String? jenisStop) {
    if (jenisStop == 'gudang') return 'Gudang';
    if (jenisStop == 'drop_point') return 'Gateway';
    return 'Seller';
  }

  String get _currentDestinationType =>
      _getJenisLokasi(_currentSeller?.jenisStop);

  String get _originWarehouseName {
    if (_allSellers.isNotEmpty) {
      final firstStop = _allSellers.first;
      if (firstStop.name.trim().isNotEmpty) {
        return firstStop.name;
      }
    }
    return 'Gudang Outgoing Utama';
  }

  List<dynamic> _vehicles = [];
  String? _selectedVehiclePlat;
  String? _selectedVehicleType;

  bool _isTripStarted = false;
  bool _isEntireRouteCompleted = false;
  // Setelah user tekan "Kembali ke Beranda" dari layar selesai,
  // tahan agar polling tidak langsung kembalikan layar completed.
  // Akan reset HANYA ketika server mengirim ritase aktif baru.
  bool _suppressCompletedState = false;
  SellerDummy? _currentSeller;
  TripStage _currentStage = TripStage.loadingGoods;

  final List<CompletedStop> _completedStops = [];

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

  Timer? _stopwatchTimer;
  Timer? _watchdogTimer;
  Timer? _routePollingTimer;
  int _activeStageSeconds = 0;

  /// Baseline stage aktif dari server (created_at event status terakhir).
  /// Dipakai supaya durasi stage gak reset ke 0 tiap app dibuka lagi.
  DateTime? _stageStartedAt;
  final Map<TripStage, int> _currentStageDurations = {};

  double _latitude = -6.2024;
  double _longitude = 106.6522;
  int _currentSpeedKmH = 0;

  int _idDriver = 3;
  int _idKendaraan = 2;
  int _idRitase = 4;
  String _driverName = 'AWALUDIN';

  // ── Konstanta Smart GPS Tracking ──
  static const int _gpsRefreshEveryTicks = 8;
  static const int _movingSendSeconds = 8;
  static const int _stationarySendSeconds = 60;
  static const double _speedThresholdKmh = 5;
  static const double _moveThresholdDeg = 0.00005;

  int _gpsTick = 0;
  double? _lastSentLat;
  double? _lastSentLng;
  DateTime? _lastSentTime;
  DateTime? _prevFixTime;
  double? _prevLat;
  double? _prevLng;

  // ── Animation ──
  final List<bool> _cardVisible = [false, false, false];
  final List<AnimationController?> _cardControllers = [];

  // ── Guard izin lokasi ──
  // `_checkingPermission`: cegah panggilan bertumpuk (initState + resume
  // + requestPermission yang memicu lifecycle) → dialog lokasi numpuk.
  // `_alwaysPromptedThisSession`: dialog "Live tracking saat layar mati"
  // cuma muncul SEKALI per sesi app, bukan tiap balik dari background.
  bool _checkingPermission = false;
  bool _alwaysPromptedThisSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadConfig();
    _ensureLocationPermission();
    ApiClient.markAppOpen();
    _startWatchdog();
    _startRoutePollingTimer();
  }

  /// Watchdog tiap 30 detik: kalau service background mati (di-kill OS),
  /// auto-restart biar GPS tetap terkirim walau layar mati.
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      ensureTrackingRunning();
    });
  }

  void _startRoutePollingTimer() {
    _routePollingTimer?.cancel();
    _routePollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      _fetchActiveRitase(isSilentCheck: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Saat app balik ke foreground: recompute durasi stage dari baseline
    // (timer Dart pause saat layar mati → _activeStageSeconds ketinggalan),
    // plus kirim tracking biar dashboard langsung update posisi.
    if (state == AppLifecycleState.resumed) {
      ApiClient.markAppOpen();
      if (_isTripStarted && _stageStartedAt != null) {
        setState(() {
          _activeStageSeconds = DateTime.now()
              .difference(_stageStartedAt!)
              .inSeconds;
        });
      }
      // Re-check izin & auto-start service: user mungkin baru balik dari
      // Settings setelah mengubah izin lokasi → langsung nyalakan tracking.
      _ensureLocationPermission();
      _sendInstantTracking();
    }
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
    _animateCardsIn();
  }

  void _animateCardsIn() {
    for (int i = 0; i < _cardVisible.length; i++) {
      Future.delayed(Duration(milliseconds: 100 + i * 80), () {
        if (mounted) {
          setState(() {
            _cardVisible[i] = true;
          });
        }
      });
    }
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
        if (current is Map) {
          _selectedVehiclePlat = current['plat']?.toString();
          _selectedVehicleType = current['type']?.toString();
        }
      } catch (_) {}
    });
  }

  Future<void> _fetchActiveRitase({bool isSilentCheck = false}) async {
    if (_idKendaraan == 0) return;

    final data = await ApiClient.fetchActiveRitase(_idDriver, _idKendaraan);
    if (!mounted) return;

    if (data != null && data['has_active_ritase'] == true) {
      // Ada ritase baru → izinkan completed state normal kembali
      _suppressCompletedState = false;
      final rawStops = data['stops'];
      final stops = rawStops is List ? rawStops : const <dynamic>[];
      final parsedSellers = stops.whereType<Map>().map((m) {
        return SellerDummy(
          id: (m['id_stop'] ?? '').toString(),
          name: m['nama_lokasi']?.toString() ?? '',
          address: m['alamat']?.toString() ?? '',
          phone: m['no_hp']?.toString() ?? '-',
          estimatedAwb: 20,
          totalKoli: 15,
          jenisStop: m['jenis_stop']?.toString() ?? 'seller',
          latitude: m['latitude'] != null
              ? (m['latitude'] as num).toDouble()
              : null,
          longitude: m['longitude'] != null
              ? (m['longitude'] as num).toDouble()
              : null,
        );
      }).toList();

      final stageStartedAt = DateTime.tryParse(
        data['stage_started_at']?.toString() ?? '',
      );
      // Progress resume dari server: index stop yang sedang dikerjakan +
      // status stage terakhir (biar app yang di-kill & dibuka lagi LANJUT,
      // bukan mulai ulang dari stop pertama).
      final stopIndex = (data['current_stop_index'] as num?)?.toInt() ?? 0;
      final lastStatus = data['last_status']?.toString() ?? '';

      // Cek apakah ada perubahan rute dibanding yang ditampilkan sekarang
      bool routeChanged = false;
      if (isSilentCheck && _allSellers.isNotEmpty) {
        if (_allSellers.length != parsedSellers.length) {
          routeChanged = true;
        } else {
          for (int i = 0; i < _allSellers.length; i++) {
            if (_allSellers[i].id != parsedSellers[i].id ||
                _allSellers[i].name != parsedSellers[i].name) {
              routeChanged = true;
              break;
            }
          }
        }
      }

      // Anti-manipulasi: kalau trip SUDAH mulai di sesi ini, pertahankan
      // state aktifnya (jangan reset walau ini hasil refresh).
      if (_isTripStarted && _currentSeller != null) {
        setState(() {
          _idRitase = data['id_ritase'] ?? 0;
          _isLastRitase = data['is_last_ritase'] == true;
          _allSellers = parsedSellers;
        });
        await ApiClient.saveDriverConfig(
          idDriver: _idDriver,
          idKendaraan: _idKendaraan,
          idRitase: _idRitase,
        );
        return;
      }

      // Belum mulai → simpan sebagai "jadwal aktif" yang menunggu keputusan
      // user. Tombol Mulai/Lanjutkan muncul, bukan auto-start trip.
      setState(() {
        _idRitase = data['id_ritase'] ?? 0;
        _isLastRitase = data['is_last_ritase'] == true;
        _allSellers = parsedSellers;
        _stageStartedAt = stageStartedAt;

        if (!_isTripStarted || _currentSeller == null) {
          final idx = stopIndex.clamp(0, parsedSellers.length - 1);
          _currentSeller = parsedSellers.isNotEmpty ? parsedSellers[idx] : null;
          _currentStage = _mapStatusToStage(lastStatus);
          _activeStageSeconds = _stageStartedAt != null
              ? DateTime.now().difference(_stageStartedAt!).inSeconds
              : 0;
          _isTripStarted = false;
          _isEntireRouteCompleted = false;
          _currentStageDurations.clear();
          _completedStops.clear();
        }
      });

      if (routeChanged && mounted) {
        _showRouteUpdatedNotification();
      }

      if (_isTripStarted && !_isEntireRouteCompleted) {
        _startTimer();
      }
      await ApiClient.saveDriverConfig(
        idDriver: _idDriver,
        idKendaraan: _idKendaraan,
        idRitase: _idRitase,
      );
    } else if (data != null && data['all_completed'] == true) {
      // Jika user baru saja tekan "Kembali ke Beranda" dari layar selesai,
      // jangan tampilkan layar completed lagi sampai flag di-reset.
      if (_suppressCompletedState) return;
      setState(() {
        _idRitase = 0;
        _isTripStarted = true;
        _isEntireRouteCompleted = true;
      });
    } else {
      bool wasActive = _allSellers.isNotEmpty || _isTripStarted;
      setState(() {
        _idRitase = 0;
        _allSellers.clear();
        _isTripStarted = false;
        _isEntireRouteCompleted = false;
      });
      if (isSilentCheck && wasActive && mounted) {
        _showRouteDeletedNotification();
      }
    }
  }

  /// Map status event server → stage mobile (buat resume setelah app di-kill).
  TripStage _mapStatusToStage(String status) {
    final s = status.toLowerCase();
    if (s.contains('menuju')) return TripStage.enRoute;
    if (s.contains('tiba')) return TripStage.arrived;
    if (s.contains('selesai')) return TripStage.completed;
    return TripStage.loadingGoods; // bongkar muat / default
  }

  Future<void> _ensureLocationPermission() async {
    // Guard: kalau check lagi sedang jalan (misal dipanggil lagi dari resume
    // saat requestPermission memicu lifecycle), skip biar gak numpuk dialog.
    if (_checkingPermission) return;
    _checkingPermission = true;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack(
          'Layanan lokasi HP dimatikan. Aktifkan untuk live tracking.',
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      // Android 10+: background GPS butuh "Always". Prompt kedua biasanya
      // menawarkan "Allow all the time" — minta sekali lagi biar muncul.
      if (permission == LocationPermission.whileInUse) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _showSnack('Izin lokasi ditolak. Live tracking tidak berjalan.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _showSnack(
          'Izin lokasi ditolak permanen. Buka pengaturan HP dan izinkan "Selalu".',
        );
        return;
      }
      if (permission == LocationPermission.whileInUse) {
        // Masih "saat app digunakan" → minta user set "Selalu" manual lewat settings.
        // Tanpa ini posisi berhenti terkirim saat layar mati (aturan Android).
        // Prompt cuma SEKALI per sesi — kalau user pilih "Nanti", jangan
        // ganggu lagi tiap balik dari background (tapi tetap cek di bawah).
        if (!mounted) return;
        if (!_alwaysPromptedThisSession) {
          _alwaysPromptedThisSession = true;
          final goSettings = await AppDialog.confirm(
            context: context,
            icon: Icons.location_on_rounded,
            iconColor: AppColors.orange,
            title: 'Perizinan akses gps',
            message:
                'Agar posisi armada tetap dapat dipantau walau layar HP mati, pilih '
                '"Izinkan semua waktu" (Allow all the time) di pengaturan lokasi MUSTGO.',
            actionLabel: 'Buka Pengaturan',
            cancelLabel: 'Nanti',
          );
          if (goSettings == true) {
            await Geolocator.openAppSettings();
            // User balik dari Settings → re-check. Kalau sudah "Always", service
            // langsung start; kalau masih belum, kasih tahu biar tracking foreground
            // tetap jalan (layar aktif) walaupun layar mati belum bisa.
            if (!mounted) return;
            permission = await Geolocator.checkPermission();
            if (permission == LocationPermission.always) {
              try {
                await startBackgroundTracking();
              } catch (_) {}
              await _refreshLocation();
              return;
            }
            if (permission != LocationPermission.denied &&
                permission != LocationPermission.deniedForever) {
              _showSnack(
                'Izin lokasi belum "Semua waktu". Tracking tetap jalan saat app '
                'terbuka, tapi berhenti saat layar mati.',
              );
            }
          }
        } else {
          // Sudah pernah ditanya di sesi ini → diam-diam pastikan service
          // foreground tetap hidup (tanpa modal).
          try {
            await startBackgroundTracking();
          } catch (_) {}
        }
        return;
      }
      // Sudah "Always" → pastikan foreground service hidup (kirim GPS tiap 30s).
      try {
        await startBackgroundTracking();
      } catch (_) {}
      await _refreshLocation();
    } finally {
      _checkingPermission = false;
    }
  }

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
      final speedMs = pos.speed < 0 ? 0.0 : pos.speed;
      var speedKmh = (speedMs * 3.6).round();

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
        if (dt > 0) speedKmh = ((dist / dt) * 3.6).round();
      }

      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _currentSpeedKmH = speedKmh;
      });

      _prevLat = pos.latitude;
      _prevLng = pos.longitude;
      _prevFixTime = now;
    } catch (_) {}
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopwatchTimer?.cancel();
    _watchdogTimer?.cancel();
    _routePollingTimer?.cancel();
    _awbInputController.dispose();
    _koliInputController.dispose();
    _ecerInputController.dispose();
    for (final c in _cardControllers) {
      c?.dispose();
    }
    super.dispose();
  }

  void _showRouteUpdatedNotification() {
    AppDialog.confirm(
      context: context,
      icon: Icons.edit_notifications_rounded,
      iconColor: AppColors.orange,
      title: 'Perubahan Rute dari Tower Controll',
      message:
          'Koordinator baru saja memperbarui rute perjalanan Anda. Tampilan perhentian di layar HP Anda telah disesuaikan secara otomatis.',
      actionLabel: 'Mengerti',
      cancelLabel: 'Tutup',
    );
  }

  void _showRouteDeletedNotification() {
    AppDialog.confirm(
      context: context,
      icon: Icons.delete_sweep_rounded,
      iconColor: AppColors.error,
      title: 'Rute Dihapus oleh Admin',
      message:
          'Jadwal rute perjalanan Anda telah dihapus oleh Admin. Tampilan aplikasi telah dikembalikan ke Halaman Beranda.',
      actionLabel: 'Mengerti',
      cancelLabel: 'Tutup',
    );
  }

  void _startTimer() {
    _stopwatchTimer?.cancel();
    _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_isTripStarted && !_isEntireRouteCompleted) {
          _activeStageSeconds++;

          _gpsTick++;
          if (_gpsTick % _gpsRefreshEveryTicks == 0) {
            _refreshLocation();
          }

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
              final secSince = now.difference(_lastSentTime!).inSeconds;
              if (secSince >= _movingSendSeconds) {
                _sendInstantTracking(speed: _currentSpeedKmH);
              }
            } else {
              final secSince = now.difference(_lastSentTime!).inSeconds;
              if (secSince >= _stationarySendSeconds) {
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

  void _stopTimer() => _stopwatchTimer?.cancel();

  void _resetSimulation() {
    _stopTimer();
    // Tahan layar completed sampai ada ritase aktif baru dari server
    _suppressCompletedState = true;
    setState(() {
      _isTripStarted = false;
      _isEntireRouteCompleted = false;
      _currentSeller = null;
      _currentStage = TripStage.loadingGoods;
      _activeStageSeconds = 0;
      _stageStartedAt = null;
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
    // Langsung fetch sekali untuk update UI, tapi flag tetap aktif
    _fetchActiveRitase();
  }

  void _startTripDirectly(SellerDummy seller) {
    setState(() {
      _currentSeller = seller;
      _isTripStarted = true;
      _currentStage = TripStage.loadingGoods;
      _stageStartedAt = DateTime.now();
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
    ApiClient.sendStatusUpdate(
      idRitase: _idRitase,
      status: 'mulai_loading',
      latitude: _latitude,
      longitude: _longitude,
      koli: _currentActualKoli,
      ecer: _currentActualEcer,
      durasiDetik: 0,
      namaLokasi: seller.name,
    );
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
    final targetStage = stage ?? _currentStage;
    String? locName = _currentSeller?.name;
    if (targetStage == TripStage.enRoute || targetStage == TripStage.arrived) {
      if (_allSellers.isNotEmpty &&
          _completedStops.length + 1 < _allSellers.length) {
        locName = _allSellers[_completedStops.length + 1].name;
      }
    } else if (targetStage == TripStage.completed) {
      locName = _allSellers.isNotEmpty ? _allSellers.last.name : 'Selesai';
    }

    ApiClient.sendTrackingData(
      latitude: _latitude,
      longitude: _longitude,
      speed: speed ?? _currentSpeedKmH,
      status: _stageToStatusKey(targetStage),
      koli: _currentActualKoli,
      ecer: _currentActualEcer,
      durasiDetik: durasiDetik,
      idDriver: _idDriver,
      idKendaraan: _idKendaraan,
      idRitase: _idRitase,
      namaLokasi: locName,
    );
  }

  String _stageToStatusKey(TripStage stage) {
    switch (stage) {
      case TripStage.loadingGoods:
        return 'mulai_loading';
      case TripStage.enRoute:
        return 'menuju_seller';
      case TripStage.arrived:
        return 'tiba';
      case TripStage.completed:
        return 'selesai';
    }
  }

  String get _currentStageTitle {
    final currLoc = _currentDestinationType;
    String? destName;
    if (_allSellers.isNotEmpty &&
        _completedStops.length + 1 < _allSellers.length) {
      destName = _allSellers[_completedStops.length + 1].name;
    }

    switch (_currentStage) {
      case TripStage.loadingGoods:
        return 'Bongkar Muat Barang';
      case TripStage.enRoute:
        return 'Menuju ${destName ?? currLoc}';
      case TripStage.arrived:
        return 'Tiba di ${destName ?? currLoc}';
      case TripStage.completed:
        return 'Selesai';
    }
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
                      if (v is! Map) {
                        return const ListTile(title: Text('-'));
                      }
                      final isSelected = _idKendaraan == v['id'];
                      return ListTile(
                        leading: Icon(
                          Icons.local_shipping,
                          color: isSelected ? AppColors.navy : Colors.grey,
                        ),
                        title: Text(v['plat']?.toString() ?? '-'),
                        subtitle: Text('${v['type']} - ${v['capacity_kg']}kg'),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: AppColors.navy,
                              )
                            : null,
                        onTap: () async {
                          Navigator.pop(ctx);
                          setState(() {
                            _idKendaraan = _toInt(v['id']);
                            _selectedVehiclePlat = v['plat']?.toString();
                            _selectedVehicleType = v['type']?.toString();
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

  void _showChangePasswordDialog() {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool loading = false;

    AppDialog.showStateful(
      context: context,
      icon: Icons.lock_reset_rounded,
      iconColor: AppColors.navy,
      title: 'Ganti Password',
      builder: (dialogCtx, setDialogState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: oldCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password Lama',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password Baru',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Konfirmasi Password Baru',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppDialog.cancelButton(
                  label: 'Batal',
                  onPressed: loading ? () {} : () => Navigator.pop(dialogCtx),
                ),
                const SizedBox(width: 8),
                AppDialog.actionButton(
                  label: 'Simpan',
                  color: AppColors.navy,
                  onPressed: loading
                      ? () {}
                      : () async {
                          final old = oldCtrl.text.trim();
                          final newP = newCtrl.text;
                          final conf = confirmCtrl.text;
                          String? err;
                          if (old.isEmpty || newP.isEmpty) {
                            err = 'Semua field wajib diisi.';
                          } else if (newP.length < 6) {
                            err = 'Password baru minimal 6 karakter.';
                          } else if (newP != conf) {
                            err = 'Konfirmasi password tidak sama.';
                          }
                          if (err != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(err),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          setDialogState(() => loading = true);
                          try {
                            await ApiClient.changePassword(
                              oldPassword: old,
                              newPassword: newP,
                            );
                            if (!dialogCtx.mounted) return;
                            Navigator.pop(dialogCtx);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Password berhasil diubah. Silakan login ulang.',
                                ),
                                backgroundColor: AppColors.navy,
                              ),
                            );
                            await _forceRelogin();
                          } catch (e) {
                            if (!dialogCtx.mounted) return;
                            setDialogState(() => loading = false);
                            ScaffoldMessenger.of(dialogCtx).showSnackBar(
                              SnackBar(
                                content: Text(e.toString()),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                ),
              ],
            ),
          ],
        );
      },
    ).then((_) {
      oldCtrl.dispose();
      newCtrl.dispose();
      confirmCtrl.dispose();
    });
  }

  Future<void> _forceRelogin() async {
    await AuthService.logout();
    try {
      await stopBackgroundTracking();
    } catch (_) {}
    try {
      await ApiClient.clearDriverConfig();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _confirmCancelTrip() async {
    // Jika perjalanan sudah selesai seluruhnya → langsung kembali ke beranda
    // tanpa dialog konfirmasi, dan JANGAN reset state (biar kartu selesai
    // tetap tampil di beranda).
    if (_isEntireRouteCompleted) {
      _stopwatchTimer?.cancel();
      setState(() {
        _isTripStarted = false;
      });
      return;
    }

    final confirm = await AppDialog.confirm(
      context: context,
      icon: Icons.home_work_outlined,
      iconColor: AppColors.orange,
      title: 'Kembali ke Halaman Persiapan?',
      message:
          'Apakah Anda yakin ingin membatalkan mode perjalanan dan kembali ke Beranda Persiapan Driver?',
      actionLabel: 'Ya, Kembali ke Beranda',
      cancelLabel: 'Batal',
    );

    if (confirm == true && mounted) {
      _stopwatchTimer?.cancel();
      setState(() {
        _isTripStarted = false;
        _currentStage = TripStage.loadingGoods;
      });
      _showSnack('Kembali ke Halaman Beranda (Persiapan Driver).');
    }
  }

  Future<void> _confirmLogout() async {
    final confirm = await AppDialog.confirm(
      context: context,
      icon: Icons.logout_rounded,
      iconColor: AppColors.error,
      title: 'Konfirmasi Logout',
      message: _isTripStarted
          ? 'Perjalanan sedang aktif. Apakah Anda yakin ingin membatalkan perjalanan & keluar dari akun ini?'
          : 'Apakah Anda yakin ingin keluar dari akun ini?',
      actionLabel: 'Keluar',
      destructive: true,
    );

    if (confirm == true && mounted) {
      await AuthService.logout();
      try {
        await stopBackgroundTracking();
      } catch (_) {}
      try {
        await ApiClient.clearDriverConfig();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _confirmAndNextStage() {
    AppDialog.show(
      context: context,
      icon: Icons.help_outline_rounded,
      iconColor: AppColors.orange,
      title: 'Konfirmasi Status',
      content: Text.rich(
        TextSpan(
          text: 'Status ke:\n\n',
          style: const TextStyle(fontSize: 14, color: Colors.black87),
          children: [
            TextSpan(
              text: _getNextStageButtonLabel(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            const TextSpan(text: '?'),
          ],
        ),
      ),
      actions: [
        AppDialog.cancelButton(
          label: 'Batal',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppDialog.actionButton(
          label: 'Ya, Lanjutkan',
          onPressed: () {
            Navigator.of(context).pop();
            _nextStage();
          },
        ),
      ],
    );
  }

  void _nextStage() {
    if (_currentStage == TripStage.loadingGoods) {
      final inputKoli = int.tryParse(_koliInputController.text.trim()) ?? 0;
      final inputEcer = int.tryParse(_ecerInputController.text.trim()) ?? 0;
      _currentActualKoli += inputKoli;
      _currentActualEcer += inputEcer;
    }

    final finishedStage = _currentStage;
    final finishedDuration =
        _currentStageDurations[finishedStage] ?? _activeStageSeconds;

    setState(() {
      _currentStageDurations[_currentStage] = _activeStageSeconds;
      _activeStageSeconds = 0;

      switch (_currentStage) {
        case TripStage.loadingGoods:
          _currentStage = TripStage.enRoute;
          break;
        case TripStage.enRoute:
          _currentStage = TripStage.arrived;
          break;
        case TripStage.arrived:
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
          final nextOriginIndex = _completedStops.length;
          if (nextOriginIndex < _allSellers.length - 1) {
            _currentSeller = _allSellers[nextOriginIndex];
            _currentStage = TripStage.loadingGoods;
            _currentStageDurations.clear();
            _currentActualAwb = 0;
            // koli & ecer NOT reset — carry forward running total across stops
            _awbInputController.text = '0';
            _koliInputController.text = '0';
            _ecerInputController.text = '0';
          } else {
            _currentStage = TripStage.completed;
          }
          break;
        case TripStage.completed:
          break;
      }

      // Stage baru dimulai SEKARANG — baseline waktu nyata (tahan layar mati).
      // Backend juga hitung durasi dari selisih created_at, jadi konsisten.
      _stageStartedAt = DateTime.now();
    });

    // Determine location name for the NEW stage (_currentStage)
    String? locationName = _currentSeller?.name;
    if (_currentStage == TripStage.enRoute ||
        _currentStage == TripStage.arrived) {
      if (_allSellers.isNotEmpty &&
          _completedStops.length + 1 < _allSellers.length) {
        locationName = _allSellers[_completedStops.length + 1].name;
      }
    } else if (_currentStage == TripStage.completed) {
      locationName = _allSellers.isNotEmpty ? _allSellers.last.name : 'Selesai';
    }

    ApiClient.sendStatusUpdate(
      idRitase: _idRitase,
      status: _stageToStatusKey(_currentStage),
      latitude: _latitude,
      longitude: _longitude,
      koli: _currentActualKoli,
      ecer: _currentActualEcer,
      durasiDetik:
          0, // durasi dihitung dari selisih created_at antar event di web
      namaLokasi: locationName,
    );

    _sendInstantTracking(durasiDetik: finishedDuration);
  }

  Future<void> _finishEntireRoute() async {
    final wasLast = _isLastRitase;
    _stopTimer();

    final success = await ApiClient.finishRitase(_idRitase);
    if (!success) {
      _showSnack('Gagal menyelesaikan ritase di server');
      return;
    }

    setState(() {
      _isTripStarted = false;
      _completedStops.clear();
      _currentStage = TripStage.loadingGoods;
      _activeStageSeconds = 0;
      _currentStageDurations.clear();
    });

    await _fetchActiveRitase();

    if (_idRitase != 0 && !wasLast) {
      // Ritase berikutnya tersedia → TIDAK auto-start. `_fetchActiveRitase`
      // sudah menyimpan sebagai jadwal aktif (`_hasActiveRitase`), tinggal
      // tampilkan tombol "Mulai Perjalanan" lagi — user yang memutuskan.
      _showSnack('Rute berikutnya siap. Tekan Mulai Perjalanan untuk lanjut.');
    } else {
      setState(() {
        _isEntireRouteCompleted = true;
      });
      _showSnack('Seluruh jadwal hari ini telah selesai!');
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatReadableDuration(int seconds) {
    if (seconds < 60) return '$seconds dtk';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (s == 0) return '$m mnt';
    return '$m mnt $s dtk';
  }

  void _confirmExitApp() {
    AppDialog.confirm(
      context: context,
      icon: Icons.logout_rounded,
      iconColor: AppColors.navy,
      title: 'Keluar Aplikasi',
      message: 'Yakin mau keluar dari aplikasi?',
      actionLabel: 'Keluar',
      destructive: true,
    ).then((confirmed) async {
      if (confirmed != true || !mounted) return;
      // Keluar beneran: matiin tracking + kasih tau backend biar
      // armada langsung Offline di dashboard (gak nunggu ambang 3 mnt).
      try {
        await sendOfflineSignal();
      } catch (_) {}
      try {
        await stopBackgroundTracking();
      } catch (_) {}
      if (!mounted) return;
      SystemNavigator.pop();
    });
  }

  // ═══════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Anti-manipulasi: selama trip aktif, back DIBLOKIR — driver wajib
        // selesaikan rute dulu (gak bisa kabur dari tracking seenaknya).
        if (_isTripStarted && !_isEntireRouteCompleted) {
          _showSnack('Selesaikan perjalanan dulu sebelum keluar.');
          return;
        }
        _confirmExitApp();
      },
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        body: RefreshIndicator(
          onRefresh: () async {
            await _fetchActiveRitase();
          },
          color: AppColors.navy,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Header ──
              _buildHeader(),
              // ── Body ──
              SliverToBoxAdapter(
                child: _isTripStarted ? _buildTripBody() : _buildHomeBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header (gradient + wave + logo + sapaan) ──
  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.navyGradient),
        child: Stack(
          children: [
            // Wave background
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: CustomPaint(
                size: Size(MediaQuery.of(context).size.width, 20),
                painter: _WavePainter(),
              ),
            ),
            // Content
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.of(context).padding.top + 16,
                20,
                35,
              ),
              child: Row(
                children: [
                  if (_isTripStarted)
                    IconButton(
                      onPressed: _confirmCancelTrip,
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      tooltip: 'Kembali ke Beranda Persiapan',
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Image.asset(
                        'assets/images/logo_mustgo.png',
                        width: 36,
                        height: 36,
                        errorBuilder: (context, error, stack) {
                          return const Icon(
                            Icons.local_shipping_rounded,
                            size: 32,
                            color: Colors.white,
                          );
                        },
                      ),
                    ),
                  const SizedBox(width: 14),
                  // Sapaan
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hai, $_driverName!',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isTripStarted
                              ? _currentStageTitle
                              : 'Siap bertugas hari ini?',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Truck illustration
                  if (!_isTripStarted)
                    Image.asset(
                      'assets/images/truck_illustration.png',
                      width: 100,
                      height: 60,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) {
                        return Icon(
                          Icons.local_shipping_rounded,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.3),
                        );
                      },
                    ),
                  // Settings menu
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    color: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (value) {
                      if (value == 'password') {
                        _showChangePasswordDialog();
                      } else if (value == 'permissions') {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PermissionGuideScreen(),
                          ),
                        );
                      } else if (value == 'reset_trip') {
                        _confirmCancelTrip();
                      } else if (value == 'logout') {
                        _confirmLogout();
                      }
                    },
                    itemBuilder: (_) => [
                      if (_isTripStarted && !_isEntireRouteCompleted)
                        const PopupMenuItem(
                          value: 'reset_trip',
                          height: 44,
                          child: Row(
                            children: [
                              Icon(
                                Icons.home_work_outlined,
                                size: 18,
                                color: AppColors.orange,
                              ),
                              SizedBox(width: 10),
                              Text('Kembali ke Beranda (Persiapan)'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'password',
                        height: 44,
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_reset_rounded,
                              size: 18,
                              color: AppColors.navy,
                            ),
                            SizedBox(width: 10),
                            Text('Ganti Password'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'permissions',
                        height: 44,
                        child: Row(
                          children: [
                            Icon(
                              Icons.settings_suggest_rounded,
                              size: 18,
                              color: AppColors.navy,
                            ),
                            SizedBox(width: 10),
                            Text('Persiapan Tracking'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'logout',
                        height: 44,
                        child: Row(
                          children: [
                            Icon(
                              Icons.logout_rounded,
                              size: 18,
                              color: AppColors.error,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Logout',
                              style: TextStyle(color: AppColors.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Home body ──
  Widget _buildHomeBody() {
    // Jika seluruh perjalanan sudah selesai → tampilkan kartu selesai
    // di beranda (menggantikan VehicleCard + OriginCard + EmptyState).
    if (_isEntireRouteCompleted) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _buildEntireRouteCompletedCard(),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vehicle
          AnimatedOpacity(
            opacity: _cardVisible[0] ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            child: AnimatedSlide(
              offset: _cardVisible[0] ? Offset.zero : const Offset(0, 0.1),
              duration: const Duration(milliseconds: 400),
              child: VehicleCard(
                plat: _selectedVehiclePlat ?? 'B 9806 UXV',
                type: _selectedVehicleType ?? 'CDDL',
                capacity: '7.000 kg',
                onTap: _showVehicleSelection,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Origin
          AnimatedOpacity(
            opacity: _cardVisible[1] ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            child: AnimatedSlide(
              offset: _cardVisible[1] ? Offset.zero : const Offset(0, 0.1),
              duration: const Duration(milliseconds: 400),
              child: OriginCard(warehouseName: _originWarehouseName),
            ),
          ),
          const SizedBox(height: 12),
          // Empty state or CTA
          if (_allSellers.isEmpty)
            _buildEmptyState()
          else
            _buildStartButton(),
          // Completed stops history
          if (_completedStops.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildCompletedStopsHistoryCard(),
          ],
        ],
      ),
    );
  }

  // ── Trip body (during trip) ──
  Widget _buildTripBody() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current destination
          if (_currentSeller != null && !_isEntireRouteCompleted)
            _buildActiveTripSellerCard(),
          const SizedBox(height: 12),
          // Completed history
          if (_completedStops.isNotEmpty) ...[
            _buildCompletedStopsHistoryCard(),
            const SizedBox(height: 12),
          ],
          if (_isEntireRouteCompleted)
            _buildEntireRouteCompletedCard()
          else if (_currentStage == TripStage.completed)
            _buildRitaseDoneCard()
          else ...[
            _buildTimelineStatusCard(),
          ],
        ],
      ),
    );
  }

  /// Shown when all stops in current ritase are done but ritase not yet finalized.
  Widget _buildRitaseDoneCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: AppColors.success, size: 48),
          const SizedBox(height: 10),
          Text(
            'Semua ${_completedStops.length} titik stop selesai!',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.success,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _finishEntireRoute,
              icon: Icon(
                _isLastRitase
                    ? Icons.check_circle_outline
                    : Icons.arrow_forward,
              ),
              label: Text(
                _isLastRitase ? 'Selesai' : 'Selesaikan & Lanjut Rute',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isLastRitase
                    ? AppColors.success
                    : AppColors.navy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ──
  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          Icon(Icons.route_outlined, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          const Text(
            'Belum ada rute hari ini',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tunggu penugasan dari admin',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              await _fetchActiveRitase();
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text(
              'Refresh',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.navy,
              side: const BorderSide(color: AppColors.navy),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── CTA button ──
  Widget _buildStartButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
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
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  // ── Active trip seller card ──
  Widget _buildActiveTripSellerCard() {
    final seller = _currentSeller;
    if (seller == null) return const SizedBox.shrink();

    final currentStopNum = _completedStops.length + 1;
    final totalStops = _allSellers.length;

    String badgeText = 'LOKASI #$currentStopNum';
    if (seller.jenisStop == 'gudang') {
      badgeText = 'GUDANG — $currentStopNum/$totalStops';
    } else if (seller.jenisStop == 'drop_point') {
      badgeText = 'GATEWAY — $currentStopNum/$totalStops';
    } else {
      badgeText = 'SELLER — $currentStopNum/$totalStops';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.orange,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badgeText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Progress dots
          Row(
            children: List.generate(totalStops, (i) {
              final isDone = i < _completedStops.length;
              final isCurrent = i == _completedStops.length;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDone
                        ? AppColors.success
                        : isCurrent
                        ? AppColors.orange
                        : AppColors.borderLight,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          // Name
          Text(
            seller.name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          // Address
          Text(
            seller.address,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Completed stops history ──
  Widget _buildCompletedStopsHistoryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, color: AppColors.success, size: 18),
              const SizedBox(width: 8),
              Text(
                'Selesai (${_completedStops.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._completedStops.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final stop = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.successBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$idx',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop.seller.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${stop.actualKoli} koli · ${stop.actualEcer} ecer · ${_formatReadableDuration(stop.totalDurationSeconds)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.done_all,
                    color: AppColors.success,
                    size: 16,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Timeline card ──
  Widget _buildTimelineStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Status Perjalanan',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              if (_currentStage != TripStage.completed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.hourglass_top,
                        size: 12,
                        color: AppColors.navy,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(_activeStageSeconds),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: AppColors.navy,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Timeline
          _buildTimeline(),
          // Input form during loading
          if (_currentStage == TripStage.loadingGoods) ...[
            const SizedBox(height: 12),
            _buildDriverFriendlyInputForm(),
          ],
          const SizedBox(height: 12),
          // Next stage button
          if (_currentStage != TripStage.completed)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _confirmAndNextStage,
                icon: const Icon(Icons.navigation_outlined, size: 20),
                label: Text(
                  _getNextStageButtonLabel(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final segmentCount = (_allSellers.length - 1).clamp(1, 99);
    final List<_TimelineStep> steps = [];

    for (int seg = 0; seg < segmentCount; seg++) {
      final origin = _allSellers[seg];
      final destination = _allSellers[seg + 1];
      final destType = _getJenisLokasi(destination.jenisStop);

      steps.add(
        _TimelineStep(
          title: 'Bongkar Muat di ${origin.name}',
          subtitle: 'Proses pengisian muatan',
          icon: Icons.inventory_2_outlined,
          segIndex: seg,
          stageIndex: 0,
        ),
      );
      steps.add(
        _TimelineStep(
          title: 'Menuju ${destination.name}',
          subtitle: 'Perjalanan ke $destType',
          icon: Icons.navigation_outlined,
          segIndex: seg,
          stageIndex: 1,
        ),
      );
      steps.add(
        _TimelineStep(
          title: 'Tiba di ${destination.name}',
          subtitle: 'Sampai di $destType',
          icon: Icons.location_on_outlined,
          segIndex: seg,
          stageIndex: 2,
        ),
      );
    }

    steps.add(
      _TimelineStep(
        title: 'Selesai',
        subtitle: 'Perjalanan selesai',
        icon: Icons.check_circle_outline,
        segIndex: segmentCount,
        stageIndex: -1,
      ),
    );

    final int currentGlobal;
    if (_currentStage == TripStage.completed) {
      currentGlobal = steps.length - 1;
    } else {
      currentGlobal = _completedStops.length * 3 + _currentStage.index;
    }

    return Column(
      children: steps.asMap().entries.map((entry) {
        final globalIdx = entry.key;
        final step = entry.value;
        final isCurrent = globalIdx == currentGlobal;
        final isPassed = globalIdx < currentGlobal;
        final isLast = globalIdx == steps.length - 1;

        int? durationSec;
        if (isPassed &&
            step.segIndex == _completedStops.length &&
            step.stageIndex >= 0) {
          durationSec =
              _currentStageDurations[TripStage.values[step.stageIndex]];
        } else if (isPassed &&
            step.segIndex < _completedStops.length &&
            step.stageIndex >= 0) {
          durationSec = _completedStops[step.segIndex]
              .stageDurations[TripStage.values[step.stageIndex]];
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isPassed
                          ? AppColors.success
                          : isCurrent
                          ? AppColors.navy
                          : AppColors.borderLight,
                      border: Border.all(
                        color: isCurrent
                            ? AppColors.orange
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      isPassed ? Icons.check : step.icon,
                      color: (isPassed || isCurrent)
                          ? Colors.white
                          : AppColors.textMuted,
                      size: 14,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: isPassed
                            ? AppColors.success
                            : AppColors.borderLight,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
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
                                fontSize: 12,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: isPassed
                                    ? AppColors.success
                                    : isCurrent
                                    ? AppColors.navy
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                          if (durationSec != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.successBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _formatReadableDuration(durationSec),
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.success,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        step.subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: isCurrent
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
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
  }

  // ── Driver input form ──
  Widget _buildDriverFriendlyInputForm() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.touch_app,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Input Muatan Barang',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildVerticalStepperControl(
            label: 'Jumlah Koli (Box/Paket)',
            controller: _koliInputController,
            icon: Icons.inventory_2,
            color: AppColors.orange,
          ),
          const SizedBox(height: 10),
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStepperButton(
                icon: Icons.remove,
                color: AppColors.error,
                onTap: () {
                  int val = int.tryParse(controller.text.trim()) ?? 0;
                  if (val > 0) {
                    setState(() {
                      controller.text = (val - 1).toString();
                    });
                  }
                },
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _buildStepperButton(
                icon: Icons.add,
                color: AppColors.success,
                onTap: () {
                  int val = int.tryParse(controller.text.trim()) ?? 0;
                  setState(() {
                    controller.text = (val + 1).toString();
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildQuickChip(
                  controller: controller,
                  amount: 10,
                  label: '+10',
                ),
                const SizedBox(width: 6),
                _buildQuickChip(
                  controller: controller,
                  amount: 100,
                  label: '+100',
                ),
                const SizedBox(width: 6),
                _buildQuickChip(
                  controller: controller,
                  amount: 1000,
                  label: '+1000',
                ),
                const SizedBox(width: 6),
                _buildResetChip(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }

  Widget _buildQuickChip({
    required TextEditingController controller,
    required int amount,
    required String label,
  }) {
    return Material(
      color: AppColors.orange.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () {
          int val = int.tryParse(controller.text.trim()) ?? 0;
          setState(() {
            controller.text = (val + amount).toString();
          });
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.orange,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResetChip({required TextEditingController controller}) {
    return Material(
      color: AppColors.borderLight,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () {
          setState(() {
            controller.text = '0';
          });
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderLight),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(Icons.refresh, size: 12, color: AppColors.textSecondary),
              const SizedBox(width: 3),
              Text(
                'Reset',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getNextStageButtonLabel() {
    String? destName;
    if (_allSellers.isNotEmpty &&
        _completedStops.length + 1 < _allSellers.length) {
      destName = _allSellers[_completedStops.length + 1].name;
    }

    switch (_currentStage) {
      case TripStage.loadingGoods:
        return 'Selesai Loading → Berangkat';
      case TripStage.enRoute:
        return 'Sudah Tiba di ${destName ?? 'Lokasi'}';
      case TripStage.arrived:
        return 'Mulai Bongkar Muat';
      case TripStage.completed:
        return 'Selesai Perjalanan';
    }
  }

  // ── Route completed card ──
  Widget _buildEntireRouteCompletedCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 52),
          const SizedBox(height: 12),
          const Text(
            'Perjalanan Selesai!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Terima kasih sudah mengirim hari ini.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          // Tombol reset hanya tampil di beranda (bukan di trip body)
          if (!_isTripStarted) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _resetSimulation,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Siap Perjalanan Baru'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
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
}

/// Custom wave painter for header bottom edge.
class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.scaffoldBg
      ..style = PaintingStyle.fill;

    final path = Path();
    path.lineTo(0, size.height * 0.3);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.0,
      size.width * 0.5,
      size.height * 0.3,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.6,
      size.width,
      size.height * 0.2,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

int _toInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}
