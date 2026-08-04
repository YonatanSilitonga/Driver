import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_client.dart';

// Model data dummy Seller
class SellerDummy {
  final String id;
  final String name;
  final String address;
  final String phone;
  final int estimatedAwb;
  final int totalKoli;

  const SellerDummy({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.estimatedAwb,
    required this.totalKoli,
  });
}

// Model data Riwayat Stop yang Sudah Selesai
class CompletedStop {
  final SellerDummy seller;
  final int actualAwb;
  final int actualKoli;
  final int totalDurationSeconds;
  final Map<TripStage, int> stageDurations;

  CompletedStop({
    required this.seller,
    required this.actualAwb,
    required this.actualKoli,
    required this.totalDurationSeconds,
    required this.stageDurations,
  });
}

// Tahapan Status Perjalanan
enum TripStage {
  loadingGoods('Bongkar Muat Barang', 'Mengisi jumlah koli di [Nama Seller]', Icons.inventory_2_outlined),
  leavingWarehouse('Keluar Gudang', 'Truk bergerak meninggalkan area [Nama Seller]', Icons.local_shipping_outlined),
  enRoute('Menuju Seller', 'Sedang dalam perjalanan menuju lokasi tujuan', Icons.navigation_outlined),
  arrived('Tiba di Seller', 'Truk telah sampai di titik lokasi tujuan', Icons.location_on_outlined),
  completed('Selesai', 'Seluruh rangkaian penjemputan selesai', Icons.check_circle_outline);

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
  // Master Data Seller (Loaded dynamically from Backend Database)
  List<SellerDummy> _allSellers = const [
    SellerDummy(
      id: 'S01',
      name: 'SKI',
      address: 'Jl. Pajajaran XIV No.62, RT.005/RW.005, Gandasari, Kec. Jatiuwung, Kota Tangerang',
      phone: '-',
      estimatedAwb: 20,
      totalKoli: 15,
    ),
    SellerDummy(
      id: 'S02',
      name: 'TITIP AJA',
      address: 'RMM9+49Q, RT.002/RW.003, Poris Plawad, Kec. Batuceper, Kota Tangerang',
      phone: '-',
      estimatedAwb: 20,
      totalKoli: 15,
    ),
    SellerDummy(
      id: 'S03',
      name: 'Gateway Tangerang',
      address: 'Gateway Sorting Center Hub - Kota Tangerang, Banten 15111',
      phone: '-',
      estimatedAwb: 20,
      totalKoli: 15,
    ),
  ];

  // State Perjalanan Multi-Stop
  bool _isTripStarted = false;
  bool _isEntireRouteCompleted = false;
  SellerDummy? _currentSeller;
  TripStage _currentStage = TripStage.loadingGoods;

  final List<CompletedStop> _completedStops = [];

  // Controllers & State untuk Input AWB & Koli saat Bongkar Muat (Dimulai dari 0)
  final TextEditingController _awbInputController = TextEditingController(text: '0');
  final TextEditingController _koliInputController = TextEditingController(text: '0');

  int _currentActualAwb = 0;
  int _currentActualKoli = 0;

  // Timer & Real-time Location Tracking State
  Timer? _stopwatchTimer;
  int _activeStageSeconds = 0;
  // ignore: unused_field
  int _totalTripSeconds = 0;
  final Map<TripStage, int> _currentStageDurations = {};

  // Dummy Live GPS Coordinates
  double _latitude = -6.312845;
  double _longitude = 107.164532;

  // Smart tracking state variables
  double? _lastSentLat;
  double? _lastSentLng;
  DateTime? _lastMovementTime;
  DateTime? _lastSentTime;

  @override
  void initState() {
    super.initState();
    _fetchSellersFromBackend();
  }

  Future<void> _fetchSellersFromBackend() async {
    try {
      final response = await ApiClient.dio.get('/sellers');
      if (response.data['success'] == true) {
        final List list = response.data['data'] as List;
        if (list.isNotEmpty && mounted) {
          final fetched = list.map((item) {
            return SellerDummy(
              id: item['id'].toString(),
              name: item['name']?.toString() ?? '',
              address: item['address']?.toString() ?? '',
              phone: item['no_hp']?.toString() ?? '-',
              estimatedAwb: 20,
              totalKoli: 15,
            );
          }).toList();

          // Urutkan Rute Khusus AWALUDIN: 1. SKI -> 2. TITIP AJA -> 3. Gateway Tangerang
          final routeOrder = ['SKI', 'TITIP AJA', 'Gateway'];
          fetched.sort((a, b) {
            final idxA = routeOrder.indexWhere((name) => a.name.toUpperCase().contains(name.toUpperCase()));
            final idxB = routeOrder.indexWhere((name) => b.name.toUpperCase().contains(name.toUpperCase()));
            if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
            if (idxA != -1) return -1;
            if (idxB != -1) return 1;
            return 0;
          });

          setState(() {
            _allSellers = fetched;
          });
        }
      }
    } catch (_) {
      // Fallback ke dummy list jika backend offline
    }
  }

  @override
  void dispose() {
    _stopwatchTimer?.cancel();
    _awbInputController.dispose();
    _koliInputController.dispose();
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

          // Simulasi pergerakan GPS kecil secara real-time
          _latitude += 0.000012;
          _longitude += 0.000018;

          // Smart GPS Tracking upload logic
          final now = DateTime.now();
          if (_lastSentTime == null || _lastSentLat == null || _lastSentLng == null) {
            _sendInstantTracking();
          } else {
            final latDiff = (_latitude - _lastSentLat!).abs();
            final lngDiff = (_longitude - _lastSentLng!).abs();
            
            final bool isMoving = (latDiff > 0.00005 || lngDiff > 0.00005) &&
                (_currentStage == TripStage.leavingWarehouse || _currentStage == TripStage.enRoute);

            if (isMoving) {
              _lastMovementTime = now;
              
              final secondsSinceLastSent = now.difference(_lastSentTime!).inSeconds;
              if (secondsSinceLastSent >= 60) {
                _sendInstantTracking(speed: 30);
              }
            } else {
              final secondsSinceLastMove = now.difference(_lastMovementTime!).inSeconds;
              final secondsSinceLastSent = now.difference(_lastSentTime!).inSeconds;

              if (secondsSinceLastMove >= 300) {
                if (secondsSinceLastSent >= 300) {
                  _lastSentLat = _latitude;
                  _lastSentLng = _longitude;
                  _lastSentTime = now;
                  ApiClient.sendTrackingData(
                    latitude: _latitude,
                    longitude: _longitude,
                    speed: 0,
                    status: '$_currentStageTitle (Hemat Baterai)',
                    koli: _currentActualKoli,
                  );
                }
              } else {
                if (secondsSinceLastSent >= 60) {
                  _sendInstantTracking();
                }
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
      _awbInputController.text = '0';
      _koliInputController.text = '0';
      _latitude = -6.312845;
      _longitude = 107.164532;
    });
  }

  List<SellerDummy> get _availableSellers {
    final visitedIds = _completedStops.map((stop) => stop.seller.id).toSet();
    return _allSellers.where((seller) => !visitedIds.contains(seller.id)).toList();
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
      _awbInputController.text = '0';
      _koliInputController.text = '0';
    });
    _startTimer();
    _sendInstantTracking();
  }

  void _sendInstantTracking({int speed = 0}) {
    final now = DateTime.now();
    _lastSentLat = _latitude;
    _lastSentLng = _longitude;
    _lastSentTime = now;
    _lastMovementTime = now;
    ApiClient.sendTrackingData(
      latitude: _latitude,
      longitude: _longitude,
      speed: speed,
      status: _currentStageTitle,
      koli: _currentActualKoli,
    );
  }

  String get _currentStageTitle {
    switch (_currentStage) {
      case TripStage.loadingGoods:
        return 'Bongkar Muat Barang';
      case TripStage.leavingWarehouse:
        return 'Keluar Gudang';
      case TripStage.enRoute:
        return 'Menuju ${_currentSeller?.name ?? "Seller"}';
      case TripStage.arrived:
        return 'Tiba di ${_currentSeller?.name ?? "Seller"}';
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

  void _confirmAndNextStage() {
    if (_currentStage == TripStage.loadingGoods) {
      final inputKoli = int.tryParse(_koliInputController.text.trim()) ?? _currentActualKoli;

      if (inputKoli <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Silahkan isi jumlah koli yang anda bawa!',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        return;
      }
    }

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.help_outline_rounded, color: Color(0xFFFF8F00), size: 26),
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
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
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
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      final inputKoli = int.tryParse(_koliInputController.text.trim()) ?? _currentActualKoli;
      _currentActualKoli = inputKoli;
    }

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
          _currentStage = TripStage.completed;
          if (_currentSeller != null) {
            final stopTotalDuration = _currentStageDurations.values.fold(0, (sum, dur) => sum + dur);
            _completedStops.add(
              CompletedStop(
                seller: _currentSeller!,
                actualAwb: _currentActualAwb,
                actualKoli: _currentActualKoli,
                totalDurationSeconds: stopTotalDuration,
                stageDurations: Map.from(_currentStageDurations),
              ),
            );
          }
          break;
        case TripStage.completed:
          break;
      }
    });

    _sendInstantTracking();
  }

  void _finishEntireRoute() {
    _stopTimer();
    setState(() {
      _isEntireRouteCompleted = true;
    });
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

  void _handleBackToHome() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sederhana: Hai, AWALUDIN! (Tampil saat di Beranda)
            if (!_isTripStarted) ...[
              const Text(
                'Hai, AWALUDIN!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 14),
              _buildVehicleCard(),
              const SizedBox(height: 14),
            ],

            // Banner GPS Live Tracking Real-Time
            _buildGpsTrackingBanner(),
            const SizedBox(height: 14),

            // Banner Gudang Outgoing Utama
            _buildWarehouseCard(),
            const SizedBox(height: 16),

            // Tombol Mulai Perjalanan langsung di bawah Asal Gudang (saat di Beranda)
            if (!_isTripStarted) ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (_allSellers.isNotEmpty) {
                      _startTripDirectly(_allSellers.first);
                    }
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 26),
                  label: const Text(
                    'Mulai Perjalanan',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                ),
              ),
            ],

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
    );
  }

  // Card GPS Live Tracking Real-Time dengan Indikator Mode Smart Interval
  Widget _buildGpsTrackingBanner() {
    final isActive = _isTripStarted && !_isEntireRouteCompleted;
    final now = DateTime.now();
    final secondsSinceLastMove = _lastMovementTime != null ? now.difference(_lastMovementTime!).inSeconds : 0;
    final isBatterySaver = isActive && secondsSinceLastMove >= 300 && 
        (_currentStage == TripStage.loadingGoods || _currentStage == TripStage.arrived);

    final String modeLabel = !isActive
        ? 'Standby'
        : (isBatterySaver ? 'Hemat Baterai (5 mnt)' : 'Real-time (1 mnt)');

    final Color statusColor = !isActive
        ? Colors.grey
        : (isBatterySaver ? const Color(0xFFFF8F00) : Colors.green.shade700);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.2),
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
                child: Icon(Icons.satellite_alt_rounded, color: statusColor, size: 20),
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
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                              ? 'Armada diam > 5 mnt. Interval pengiriman 5 mnt (hemat baterai)'
                              : 'Armada bergerak. Mengirim koordinat setiap 1 mnt')
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
                    const Icon(Icons.my_location, size: 14, color: Color(0xFF0D47A1)),
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
                      (_currentStage == TripStage.leavingWarehouse || _currentStage == TripStage.enRoute)
                          ? '30 km/h (Berjalan)'
                          : '0 km/h (Berdiam)',
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

  // Kotak Informasi Kendaraan yang dikendarai (Plat: B 9806 UXV)
  Widget _buildVehicleCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0D47A1).withValues(alpha: 0.2)),
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
                  Icon(Icons.local_shipping_outlined, color: Color(0xFF0D47A1), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Kendaraan Operasional',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'Tersedia',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'B 9806 UXV',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.yellow,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Jenis: CDDL',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Kapasitas: 7.000 kg (7 Ton)',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
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
            child: const Icon(Icons.warehouse_outlined, color: Color(0xFF0D47A1), size: 28),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Asal Gudang',
                  style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2),
                Text(
                  'Gudang Outgoing Utama',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0D47A1)),
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green),
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
                    decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                    child: Center(
                      child: Text(
                        '$idx',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                        ),
                        Text(
                          '${stop.actualAwb} AWB, ${stop.actualKoli} Koli • Durasi: ${_formatReadableDuration(stop.totalDurationSeconds)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
    if (seller == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D47A1).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0D47A1), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8F00),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'SELLER TUJUAN #${_completedStops.length + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            seller.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  seller.address,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Timeline Status Perjalanan + Form Input Driver-Friendly di Bagian Bawah
  Widget _buildTimelineStatusCard() {
    final sellerName = _currentSeller?.name ?? 'Seller';
    final hasMoreSellers = _availableSellers.isNotEmpty;

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
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
              ),
              if (_currentStage != TripStage.completed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D47A1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top, size: 14, color: Color(0xFF0D47A1)),
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

          // Render Steps Timeline
          ...TripStage.values.map((stage) {
            final isCurrent = _currentStage == stage;
            final isPassed = stage.index < _currentStage.index;
            final isLast = stage == TripStage.completed;
            final durationInSec = _currentStageDurations[stage];

            String stageTitle = stage.title;
            if (stage == TripStage.enRoute) {
              stageTitle = 'Sedang Menuju ke ${_currentSeller?.name ?? "Seller"}';
            } else if (stage == TripStage.arrived) {
              stageTitle = 'Tiba di ${_currentSeller?.name ?? "Seller"}';
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
                            color: isCurrent ? const Color(0xFFFF8F00) : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          isPassed ? Icons.check : stage.icon,
                          color: (isPassed || isCurrent) ? Colors.white : Colors.grey,
                          size: 16,
                        ),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: isPassed ? Colors.green : Colors.grey.shade300,
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
                              Text(
                                stageTitle,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                  color: isPassed
                                      ? Colors.green[800]
                                      : isCurrent
                                          ? const Color(0xFF0D47A1)
                                          : Colors.grey[700],
                                ),
                              ),
                              if (durationInSec != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.timer, size: 11, color: Colors.green),
                                      const SizedBox(width: 3),
                                      Text(
                                        _formatReadableDuration(durationInSec),
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
                          ),
                          const SizedBox(height: 2),
                          Text(
                            stage.subtitle.replaceAll('[Nama Seller]', sellerName),
                            style: TextStyle(
                              fontSize: 11,
                              color: isCurrent ? Colors.black87 : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8F00),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Penjemputan di ${_currentSeller?.name} Selesai! ($_currentActualAwb AWB, $_currentActualKoli Koli)',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Tombol Opsi Multi-Seller
            if (hasMoreSellers) ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (_availableSellers.isNotEmpty) {
                      _startTripDirectly(_availableSellers.first);
                    }
                  },
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text(
                    'Lanjut ke Seller Berikutnya',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D47A1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            OutlinedButton(
              onPressed: _finishEntireRoute,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Selesaikan Seluruh Rute Perjalanan'),
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
                child: const Icon(Icons.touch_app, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Input Realisasi Muatan Barang',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
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
                    child: const Icon(Icons.remove, color: Colors.red, size: 28),
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
        ],
      ),
    );
  }

  String _getNextStageButtonLabel() {
    switch (_currentStage) {
      case TripStage.loadingGoods:
        return 'Selesai Muat -> Keluar Gudang';
      case TripStage.leavingWarehouse:
        return 'Keluar Gudang -> Menuju Seller';
      case TripStage.enRoute:
        return 'Tiba di Lokasi Seller';
      case TripStage.arrived:
        return 'Selesaikan Penjemputan Seller Ini';
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
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 6),
          Text(
            'Terima kasih! Seluruh seller dalam rute penugasan telah berhasil dikunjungi.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _resetSimulation,
            icon: const Icon(Icons.home),
            label: const Text(
              'Kembali ke Beranda Utama',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
