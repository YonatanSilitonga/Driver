import 'dart:async';
import 'package:flutter/material.dart';

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

// Model untuk mencatat Seller yang sudah selesai dikunjungi beserta realisasi muatan
class CompletedStop {
  final SellerDummy seller;
  final int actualAwb;
  final int actualKoli;
  final int totalDurationSeconds;
  final Map<TripStage, int> stageDurations;

  const CompletedStop({
    required this.seller,
    required this.actualAwb,
    required this.actualKoli,
    required this.totalDurationSeconds,
    required this.stageDurations,
  });
}

// Status Tahapan Perjalanan (Shopee Food Style)
enum TripStage {
  loadingGoods('Sedang Bongkar Muat Barang', 'Input muatan AWB & Koli dari seller ini', Icons.inventory_2_outlined),
  leavingWarehouse('Sedang Keluar Gudang', 'Armada siap berangkat meninggalkan area gudang', Icons.local_shipping_outlined),
  enRoute('Sedang Menuju ke Seller', 'Driver dalam perjalanan menuju lokasi seller', Icons.directions_car_outlined),
  arrived('Tiba di Seller', 'Driver telah sampai dan proses serah terima barang', Icons.storefront_outlined),
  completed('Selesai Penjemputan', 'Penjemputan di seller ini telah diselesaikan', Icons.check_circle_outline);

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
  // Master Data Dummy Seller
  final List<SellerDummy> _allSellers = const [
    SellerDummy(
      id: 'S01',
      name: 'Seller A - PT Elektronik Nusantara',
      address: 'Kawasan Industri Cikarang Blok B-12, Kab. Bekasi',
      phone: '0812-3456-7890',
      estimatedAwb: 25,
      totalKoli: 18,
    ),
    SellerDummy(
      id: 'S02',
      name: 'Seller B - Toko Komputer Jaya',
      address: 'Harco Mangga Dua, Lt. 2 No. 45, Jakarta Pusat',
      phone: '0815-9876-5432',
      estimatedAwb: 15,
      totalKoli: 12,
    ),
    SellerDummy(
      id: 'S03',
      name: 'Seller C - Gudang Fashion Maju',
      address: 'Kawasan Marunda Hub 3, Cilincing, Jakarta Utara',
      phone: '0821-1122-3344',
      estimatedAwb: 35,
      totalKoli: 25,
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
  int _totalTripSeconds = 0;
  final Map<TripStage, int> _currentStageDurations = {};

  // Dummy Live GPS Coordinates
  double _latitude = -6.312845;
  double _longitude = 107.164532;

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

  // Dapatkan daftar seller yang BELUM dikunjungi
  List<SellerDummy> get _availableSellers {
    final visitedIds = _completedStops.map((stop) => stop.seller.id).toSet();
    return _allSellers.where((seller) => !visitedIds.contains(seller.id)).toList();
  }

  void _showSellerSelectionSheet() {
    final available = _availableSellers;
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Semua seller dalam daftar telah dikunjungi!'),
          backgroundColor: Color(0xFF0D47A1),
        ),
      );
      return;
    }

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _completedStops.isEmpty
                        ? 'Pilih Seller Tujuan Pertama'
                        : 'Pilih Seller Tujuan Berikutnya (Stop #${_completedStops.length + 1})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0D47A1),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pilih lokasi penjemputan barang selanjutnya',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  ...available.map((seller) {
                    final isSelected = tempSelected?.id == seller.id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF0D47A1).withValues(alpha: 0.05) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF0D47A1) : Colors.grey.shade300,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: InkWell(
                        onTap: () {
                          setSheetState(() => tempSelected = seller);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: isSelected ? const Color(0xFF0D47A1) : Colors.grey,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      seller.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(seller.address, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Estimasi: ${seller.estimatedAwb} AWB / ${seller.totalKoli} Koli',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFFF8F00),
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
                  }),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _currentSeller = tempSelected;
                          _isTripStarted = true;
                          _currentStage = TripStage.loadingGoods;
                          _activeStageSeconds = 0;
                          _currentStageDurations.clear();

                          // Inisialisasi awal selalu 0 (kosong) untuk driver
                          _currentActualAwb = 0;
                          _currentActualKoli = 0;
                          _awbInputController.text = '0';
                          _koliInputController.text = '0';
                        });
                        _startTimer();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D47A1),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        _completedStops.isEmpty ? 'Mulai Perjalanan Rute' : 'Lanjut Perjalanan Ke Seller Ini',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
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
    // Pengecekan Validasi saat di tahap loadingGoods
    if (_currentStage == TripStage.loadingGoods) {
      final inputAwb = int.tryParse(_awbInputController.text.trim()) ?? _currentActualAwb;
      final inputKoli = int.tryParse(_koliInputController.text.trim()) ?? _currentActualKoli;

      // Jika jumlah AWB <= 0 ATAU Koli <= 0, tampilkan peringatan & gagalkan lanjut
      if (inputAwb <= 0 || inputKoli <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Silahkan isi jumlah koli dan awb yang anda bawa!',
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
        return; // Hentikan alur, jangan tampilkan dialog
      }
    }

    // Tampilkan Dialog Konfirmasi sebelum update status
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
      final inputAwb = int.tryParse(_awbInputController.text.trim()) ?? _currentActualAwb;
      final inputKoli = int.tryParse(_koliInputController.text.trim()) ?? _currentActualKoli;
      _currentActualAwb = inputAwb;
      _currentActualKoli = inputKoli;
    }

    setState(() {
      // Simpan durasi kegiatan yang baru saja diselesaikan
      _currentStageDurations[_currentStage] = _activeStageSeconds;
      _activeStageSeconds = 0; // Reset timer untuk kegiatan berikutnya

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
          // Masukkan ke riwayat CompletedStop beserta realisasi AWB & Koli
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

  int get _totalAwbCollected {
    return _completedStops.fold(0, (sum, stop) => sum + stop.actualAwb);
  }

  int get _totalKoliCollected {
    return _completedStops.fold(0, (sum, stop) => sum + stop.actualKoli);
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
                'Ya, Beranda',
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
            // Banner GPS Live Tracking Real-Time
            _buildGpsTrackingBanner(),
            const SizedBox(height: 14),

            // Banner Gudang Outgoing
            _buildWarehouseCard(),
            const SizedBox(height: 16),

            // Ringkasan Riwayat Seller yang Sudah Dikunjungi (Jika Ada)
            if (_completedStops.isNotEmpty) ...[
              _buildCompletedStopsHistoryCard(),
              const SizedBox(height: 16),
            ],

            // Tampilan Berdasarkan Status Perjalanan
            if (!_isTripStarted) ...[
              _buildStartTripCard(),
            ] else if (_isEntireRouteCompleted) ...[
              _buildEntireRouteCompletedCard(),
            ] else ...[
              _buildActiveTripSellerCard(),
              const SizedBox(height: 16),
              _buildTimelineStatusCard(),
            ],
          ],
        ),
      ),
    );
  }

  // Kartu Ringkasan Akumulasi Total Muatan (Disembunyikan)
  // ignore: unused_element
  Widget _buildSummaryMetricsHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0D47A1).withValues(alpha: 0.2)),
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
          const Text(
            'Ringkasan Muatan Perjalanan',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricItem(
                  label: 'Total AWB',
                  value: '$_totalAwbCollected Resi',
                  icon: Icons.confirmation_number_outlined,
                  color: const Color(0xFF0D47A1),
                ),
              ),
              Container(height: 30, width: 1, color: Colors.grey[300]),
              Expanded(
                child: _buildMetricItem(
                  label: 'Total KOLI',
                  value: '$_totalKoliCollected Paket',
                  icon: Icons.inventory_2_outlined,
                  color: const Color(0xFFFF8F00),
                ),
              ),
              Container(height: 30, width: 1, color: Colors.grey[300]),
              Expanded(
                child: _buildMetricItem(
                  label: 'Seller Selesai',
                  value: '${_completedStops.length} Stop',
                  icon: Icons.storefront_outlined,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildMetricItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[900]),
        ),
      ],
    );
  }

  // Banner Indikator GPS Live Tracking Real-Time
  Widget _buildGpsTrackingBanner() {
    final isActive = _isTripStarted && !_isEntireRouteCompleted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? Colors.green[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? Colors.green.shade400 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isActive ? 'GPS Live Tracking: Aktif' : 'GPS Live Tracking: Standby',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.green[800] : Colors.grey[700],
            ),
          ),
          const Spacer(),
          Text(
            '${_latitude.toStringAsFixed(6)}, ${_longitude.toStringAsFixed(6)}',
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: Colors.black87,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Asal: Gudang Outgoing Utama',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0D47A1)),
                ),
                const SizedBox(height: 2),
                Text(
                  'Hub Outgoing Cikarang Pusat - Bekasi',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Card Mulai Keberangkatan (Awal)
  Widget _buildStartTripCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0D47A1), width: 1.5),
      ),
      child: Column(
        children: [
          const Icon(Icons.directions_run_outlined, size: 48, color: Color(0xFF0D47A1)),
          const SizedBox(height: 12),
          const Text(
            'Siap Berangkat dari Gudang?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 6),
          Text(
            'Tekan tombol di bawah untuk memilih seller tujuan penjemputan paket pertama.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _showSellerSelectionSheet,
              icon: const Icon(Icons.arrow_forward),
              label: const Text(
                'Berangkat & Pilih Seller Pertama',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'Riwayat Penjemputan (${_completedStops.length} Seller)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green),
                  ),
                ],
              ),
              Text(
                '$_totalAwbCollected AWB / $_totalKoliCollected Koli',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[800]),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          ..._completedStops.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final stop = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
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
// Total timer disembunyikan
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
              stageTitle = 'Sedang Menuju ke ${_currentSeller?.id ?? "Seller"}';
            } else if (stage == TripStage.arrived) {
              stageTitle = 'Tiba di ${_currentSeller?.id ?? "Seller"}';
            }

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timeline Node (Dot & Line)
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
                  // Timeline Text Content & Log Durasi
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
                                  stageTitle,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: (isCurrent || isPassed) ? FontWeight.bold : FontWeight.normal,
                                    color: isCurrent
                                        ? const Color(0xFF0D47A1)
                                        : isPassed
                                            ? Colors.green[800]
                                            : Colors.grey[600],
                                  ),
                                ),
                              ),
                              // Lencana Durasi Kegiatan yang Sudah Selesai
                              if (isPassed && durationInSec != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.green.shade300),
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
// Live timer per-stage dihapus (1 timer saja di header)
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
                  onPressed: _showSellerSelectionSheet,
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
                      'Hitung Barang Masuk Truk',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1)),
                    ),
                    Text(
                      'Tekan tombol (+) atau (-) untuk isi jumlah AWB & Koli (Wajib > 0)',
                      style: TextStyle(fontSize: 11, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stepper AWB (Resi)
          _buildStepperRow(
            label: 'Jumlah AWB (Resi)',
            icon: Icons.confirmation_number_outlined,
            value: _currentActualAwb,
            controller: _awbInputController,
            onDecrement: () {
              if (_currentActualAwb > 0) {
                setState(() {
                  _currentActualAwb--;
                  _awbInputController.text = '$_currentActualAwb';
                });
              }
            },
            onIncrement: () {
              setState(() {
                _currentActualAwb++;
                _awbInputController.text = '$_currentActualAwb';
              });
            },
            onChanged: (val) {
              final parsed = int.tryParse(val);
              if (parsed != null) {
                setState(() => _currentActualAwb = parsed);
              }
            },
          ),

          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Stepper KOLI (Paket)
          _buildStepperRow(
            label: 'Jumlah KOLI (Paket)',
            icon: Icons.inventory_2_outlined,
            value: _currentActualKoli,
            controller: _koliInputController,
            onDecrement: () {
              if (_currentActualKoli > 0) {
                setState(() {
                  _currentActualKoli--;
                  _koliInputController.text = '$_currentActualKoli';
                });
              }
            },
            onIncrement: () {
              setState(() {
                _currentActualKoli++;
                _koliInputController.text = '$_currentActualKoli';
              });
            },
            onChanged: (val) {
              final parsed = int.tryParse(val);
              if (parsed != null) {
                setState(() => _currentActualKoli = parsed);
              }
            },
          ),
        ],
      ),
    );
  }

  // Stepper Driver-Friendly: Label di atas, tombol +/- di bawah (tidak overflow)
  Widget _buildStepperRow({
    required String label,
    required IconData icon,
    required int value,
    required TextEditingController controller,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label di atas
        Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF0D47A1)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Stepper controls di bawah label, centered
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Tombol Kurang (-) Besar
            InkWell(
              onTap: onDecrement,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade300, width: 1.5),
                ),
                child: const Icon(Icons.remove, color: Colors.red, size: 28),
              ),
            ),
            const SizedBox(width: 16),

            // Angka tengah (bisa diketik)
            SizedBox(
              width: 80,
              height: 52,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0D47A1),
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF0D47A1), width: 2),
                  ),
                ),
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 16),

            // Tombol Tambah (+) Besar
            InkWell(
              onTap: onIncrement,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade400, width: 1.5),
                ),
                child: const Icon(Icons.add, color: Colors.green, size: 28),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Card Ringkasan saat Seluruh Rute Multi-Seller Selesai
  Widget _buildEntireRouteCompletedCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade400, width: 1.5),
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events_outlined, size: 56, color: Colors.green),
          const SizedBox(height: 12),
          const Text(
            'Seluruh Rute Berhasil Diselesaikan!',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 6),
          Text(
            'Anda telah menyelesaikan penjemputan di ${_completedStops.length} Seller dengan total $_totalAwbCollected AWB dan $_totalKoliCollected Koli barang.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[800]),
          ),
          const SizedBox(height: 12),
          Text(
            'Total Waktu Operasional: ${_formatReadableDuration(_totalTripSeconds)}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green[900]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _resetSimulation,
              icon: const Icon(Icons.refresh),
              label: const Text(
                'Mulai Perjalanan Rute Baru',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getNextStageButtonLabel() {
    switch (_currentStage) {
      case TripStage.loadingGoods:
        return 'Konfirmasi & Keluar Gudang';
      case TripStage.leavingWarehouse:
        return 'Update: Menuju ke Seller';
      case TripStage.enRoute:
        return 'Update: Tiba di Seller';
      case TripStage.arrived:
        return 'Selesaikan Penjemputan Seller Ini';
      case TripStage.completed:
        return 'Selesai';
    }
  }
}
