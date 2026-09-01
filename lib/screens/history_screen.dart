import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../utils/network_exception.dart';
import '../widgets/app_colors.dart';

// ─── Tema warna (menggunakan AppColors agar persis dengan beranda) ─────────
const _navy = AppColors.navy;
const _orange = AppColors.orange;
const _scaffoldBg = AppColors.scaffoldBg;
const _green = AppColors.success;
const _amber = AppColors.amber;

class HistoryScreen extends StatefulWidget {
  final int? idDriver;
  final bool isEmbedded;
  final int refreshTrigger;
  const HistoryScreen({
    super.key,
    this.idDriver,
    this.isEmbedded = false,
    this.refreshTrigger = 0,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _selectedFilter = 'all';
  String _searchQuery = '';
  DateTimeRange? _selectedDateRange;
  bool _isLoading = true;
  String? _historyError;
  List<Map<String, dynamic>> _historyList = [];

  final _searchCtrl = TextEditingController();

  static const _filters = [
    ('all', 'Semua'),
    ('today', 'Hari Ini'),
    ('week', 'Minggu Ini'),
    ('month', 'Bulan Ini'),
    ('last_month', 'Bulan Lalu'),
    ('custom', '📅 Pilih Tanggal'),
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger ||
        oldWidget.idDriver != widget.idDriver) {
      _loadHistory();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _historyError = null;
    });
    try {
      String? startStr;
      String? endStr;
      if (_selectedFilter == 'custom' && _selectedDateRange != null) {
        startStr = "${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')}";
        endStr = "${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}";
      }
      final list = await ApiClient.fetchDriverHistory(
        idDriver: widget.idDriver,
        filter: _selectedFilter,
        startDate: startStr,
        endDate: endStr,
      );
      if (mounted) {
        setState(() {
          _historyList = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final netEx = NetworkException.from(e);
        setState(() {
          _historyError = netEx.message;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _selectedDateRange ?? DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: now,
      ),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: _navy,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedFilter = 'custom';
        _selectedDateRange = picked;
      });
      _loadHistory();
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _historyList;
    final q = _searchQuery.toLowerCase();
    return _historyList.where((it) {
      final kode = (it['kode_ritase'] ?? '').toString().toLowerCase();
      return kode.contains(q);
    }).toList();
  }

  String _durasi(int sec) {
    if (sec <= 0) return '-';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    return h > 0 ? '${h}j ${m}m' : '${m} mnt';
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filtered;
    return Scaffold(
      backgroundColor: _scaffoldBg,
      body: Column(
        children: [
          _buildHeader(),
          _buildControls(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _navy))
                : _historyError != null && shown.isEmpty
                    ? _buildErrorState()
                    : shown.isEmpty
                        ? _buildEmpty()
                        : RefreshIndicator(
                            onRefresh: _loadHistory,
                            color: _navy,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: shown.length,
                              itemBuilder: (_, i) => _HistoryCard(
                                item: shown[i],
                                durasi: _durasi,
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────
  Widget _buildHeader() {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppColors.navyGradient),
      child: Stack(
        children: [
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: CustomPaint(
              size: Size(MediaQuery.of(context).size.width, 18),
              painter: _WavePainter(),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, top + 14, 12, 28),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.history_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Riwayat Ritase',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                      Text(
                        _isLoading ? 'Memuat...' : '${_historyList.length} perjalanan tercatat',
                        style: const TextStyle(fontSize: 12, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                  onPressed: _loadHistory,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── FILTER + SEARCH ────────────────────────────────────────────
  Widget _buildControls() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _filters.map((f) {
                  final active = _selectedFilter == f.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        if (f.$1 == 'custom') {
                          _pickDateRange();
                        } else if (!active) {
                          setState(() {
                            _selectedFilter = f.$1;
                            _selectedDateRange = null;
                          });
                          _loadHistory();
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: active ? _navy : Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: active ? _navy : const Color(0xFFCBD5E1),
                            width: 1.4,
                          ),
                          boxShadow: active
                              ? [BoxShadow(color: _navy.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))]
                              : [],
                        ),
                        child: Text(f.$2,
                            style: TextStyle(
                              color: active ? Colors.white : const Color(0xFF64748B),
                              fontSize: 13,
                              fontWeight: active ? FontWeight.bold : FontWeight.w500,
                            )),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
              decoration: InputDecoration(
                hintText: 'Cari kode ritase…',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                        child: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 18),
                      )
                    : null,
                filled: true,
                fillColor: _scaffoldBg,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _navy, width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ERROR STATE ────────────────────────────────────────────────
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Gagal Memuat Riwayat',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            Text(
              _historyError ?? 'Periksa koneksi internet Anda.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadHistory,
              icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
              label: const Text('Coba Lagi', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── EMPTY STATE ────────────────────────────────────────────────
  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20)],
              ),
              child: Icon(
                _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.history_toggle_off_rounded,
                size: 56,
                color: Colors.grey.shade300,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _searchQuery.isNotEmpty ? 'Tidak ada hasil' : 'Belum Ada Riwayat',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Kode "$_searchQuery" tidak ditemukan.'
                  : 'Ritase yang sudah diselesaikan\nakan tampil di sini.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), height: 1.6),
            ),
            if (_searchQuery.isEmpty) ...[
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _loadHistory,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: _navy,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Segarkan',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  HISTORY CARD
// ─────────────────────────────────────────────────────────────────
class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String Function(int) durasi;

  const _HistoryCard({required this.item, required this.durasi});

  void _openDetail(BuildContext context) {
    final idRitase = (item['id_ritase'] as num?)?.toInt() ?? 0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetailSheet(idRitase: idRitase, headerItem: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kode = item['kode_ritase']?.toString() ?? '-';
    final tanggal = item['tanggal']?.toString() ?? '-';
    final jamMulai = item['jam_mulai']?.toString() ?? '';
    final jamSelesai = item['jam_selesai']?.toString() ?? '';
    final totalDurasi = (item['total_durasi'] as num?)?.toInt() ?? 0;
    final ritaseKe = item['ritase_ke'] ?? 1;
    final jenisRitase = item['jenis_ritase']?.toString() ?? 'Reguler';
    final totalKoli = (item['total_koli'] as num?)?.toInt() ?? 0;
    final totalEcer = (item['total_ecer'] as num?)?.toInt() ?? 0;
    final totalHV = (item['total_high_value'] as num?)?.toInt() ?? 0;
    final totalStops = (item['total_stops'] as num?)?.toInt() ?? 0;
    final hasHV = totalHV > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EDF2)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          // ── TOP: kode + status + tanggal ──────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nomor ritase
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _navy,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '$ritaseKe',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(kode,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 4),
                          Text(tanggal, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                          if (jamSelesai.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            const Text('·', style: TextStyle(color: Color(0xFF94A3B8))),
                            const SizedBox(width: 6),
                            const Icon(Icons.access_time_rounded, size: 12, color: Color(0xFF94A3B8)),
                            const SizedBox(width: 3),
                            Text('Selesai $jamSelesai', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Badge status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _green.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 12, color: _green),
                      const SizedBox(width: 4),
                      Text('Selesai',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _green)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              children: [
                // ── ROUTE FLOW ──────────────────────────────────
                _RouteFlow(jenisRitase: jenisRitase, totalStops: totalStops),
                const SizedBox(height: 14),

                // ── CARGO SPECS ─────────────────────────────────
                Row(
                  children: [
                    _cargoChip(Icons.inventory_2_rounded, '$totalKoli Koli', const Color(0xFF3B82F6)),
                    if (totalEcer > 0) ...[
                      const SizedBox(width: 8),
                      _cargoChip(Icons.shopping_basket_rounded, '$totalEcer Ecer', _orange),
                    ],
                    if (hasHV) ...[
                      const SizedBox(width: 8),
                      _hvBadge(totalHV),
                    ],
                    const Spacer(),
                    const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 3),
                    Text('$totalStops Stop',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  ],
                ),
              ],
            ),
          ),

          // ── FOOTER: durasi + tombol ──────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                // Durasi
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _scaffoldBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, size: 13, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 5),
                      Text(
                        jamMulai.isNotEmpty ? '$jamMulai – $jamSelesai' : durasi(totalDurasi),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Tombol Lihat Rincian
                GestureDetector(
                  onTap: () => _openDetail(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _navy,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 6),
                        Text('Lihat Rincian',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cargoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _hvBadge(int hv) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium_rounded, size: 12, color: _amber),
          const SizedBox(width: 4),
          Text('HV ×$hv', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _amber)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  ROUTE FLOW WIDGET
// ─────────────────────────────────────────────────────────────────
class _RouteFlow extends StatelessWidget {
  final String jenisRitase;
  final int totalStops;

  const _RouteFlow({required this.jenisRitase, required this.totalStops});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Origin
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _navy,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.4), blurRadius: 4)],
                  ),
                ),
                const SizedBox(width: 6),
                const Text('Keberangkatan', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              ],
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text('Gudang / DC', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _navy.withValues(alpha: 0.85))),
            ),
          ],
        ),

        // Garis penghubung
        Expanded(
          child: Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Garis putus
                    Row(
                      children: List.generate(12, (i) => Expanded(
                        child: Container(
                          height: 1.5,
                          color: i.isEven ? const Color(0xFFCBD5E1) : Colors.transparent,
                        ),
                      )),
                    ),
                    // Label tengah
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        '$totalStops Stop',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),

        // Destination
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                Text(jenisRitase, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                const SizedBox(width: 6),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: _green.withValues(alpha: 0.4), blurRadius: 4)],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('Gateway / Tujuan',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _green.withValues(alpha: 0.85))),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  DETAIL SHEET
// ─────────────────────────────────────────────────────────────────
class _DetailSheet extends StatefulWidget {
  final int idRitase;
  final Map<String, dynamic> headerItem;
  const _DetailSheet({required this.idRitase, required this.headerItem});

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  bool _isLoading = true;
  List<dynamic> _stops = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await ApiClient.fetchDriverHistoryDetail(widget.idRitase);
    if (mounted) setState(() { _stops = res?['stops'] ?? []; _isLoading = false; });
  }

  void _preview(String url) {
    if (url.isEmpty) return;
    final full = url.startsWith('http') ? url : '${ApiClient.baseUrl.replaceAll('/api/v1', '')}$url';
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(full, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.white, padding: const EdgeInsets.all(20),
                    child: const Text('Foto tidak dapat dimuat.'),
                  )),
            ),
            IconButton(
              icon: const CircleAvatar(backgroundColor: Colors.black54,
                  child: Icon(Icons.close, color: Colors.white, size: 18)),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kode = widget.headerItem['kode_ritase']?.toString() ?? '';
    final tanggal = widget.headerItem['tanggal']?.toString() ?? '';
    final jamMulai = widget.headerItem['jam_mulai']?.toString() ?? '';
    final jamSelesai = widget.headerItem['jam_selesai']?.toString() ?? '';

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: _scaffoldBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 0),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white54, borderRadius: BorderRadius.circular(2)),
          ),

          // Header sheet (navy)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 18),
            decoration: const BoxDecoration(
              gradient: AppColors.navyGradient,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(kode, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 11, color: Colors.white60),
                          const SizedBox(width: 4),
                          Text(tanggal, style: const TextStyle(fontSize: 11, color: Colors.white60)),
                          if (jamMulai.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.access_time_rounded, size: 11, color: Colors.white60),
                            const SizedBox(width: 4),
                            Text('$jamMulai – $jamSelesai',
                                style: const TextStyle(fontSize: 11, color: Colors.white60)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Summary bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _summaryItem(Icons.local_shipping_rounded, 'Jenis',
                    widget.headerItem['jenis_ritase']?.toString() ?? '-', _navy),
                _summaryItem(Icons.inventory_2_rounded, 'Total Koli',
                    '${(widget.headerItem['total_koli'] as num?)?.toInt() ?? 0}', const Color(0xFF3B82F6)),
                _summaryItem(Icons.location_on_rounded, 'Total Stop',
                    '${(widget.headerItem['total_stops'] as num?)?.toInt() ?? 0}', _green),
                if (((widget.headerItem['total_high_value'] as num?)?.toInt() ?? 0) > 0)
                  _summaryItem(Icons.workspace_premium_rounded, 'HV',
                      '${(widget.headerItem['total_high_value'] as num?)?.toInt() ?? 0}', _amber),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE8EDF2)),

          // Label lini masa
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(
              children: [
                Icon(Icons.timeline_rounded, size: 16, color: _navy),
                SizedBox(width: 8),
                Text('Rincian Titik Stop', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navy)),
              ],
            ),
          ),

          // Stops list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _navy))
                : _stops.isEmpty
                    ? const Center(child: Text('Tidak ada detail stop.', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: _stops.length,
                        itemBuilder: (_, i) {
                          final st = _stops[i];
                          final isLast = i == _stops.length - 1;
                          return _StopTimelineItem(
                            stop: st,
                            index: i,
                            isLast: isLast,
                            onPhotoTap: _preview,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  STOP TIMELINE ITEM
// ─────────────────────────────────────────────────────────────────
class _StopTimelineItem extends StatelessWidget {
  final dynamic stop;
  final int index;
  final bool isLast;
  final void Function(String) onPhotoTap;

  const _StopTimelineItem({
    required this.stop,
    required this.index,
    required this.isLast,
    required this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    final nama = stop['nama_lokasi']?.toString() ?? 'Lokasi';
    final alamat = stop['alamat']?.toString() ?? '';
    final jenis = stop['jenis_stop']?.toString() ?? '';
    final koli = stop['koli'] ?? 0;
    final ecer = stop['ecer'] ?? 0;
    final hv = stop['high_value'] ?? 0;
    final photo = stop['photo_url']?.toString() ?? '';
    final urutan = stop['urutan'] ?? (index + 1);

    // Warna dot berdasarkan jenis
    Color dotColor = _navy;
    IconData dotIcon = Icons.radio_button_unchecked;
    if (jenis == 'gateway') { dotColor = _green; dotIcon = Icons.flag_rounded; }
    else if (jenis == 'gudang') { dotColor = _orange; dotIcon = Icons.warehouse_rounded; }
    else if (jenis == 'seller') { dotColor = const Color(0xFF3B82F6); dotIcon = Icons.store_rounded; }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kolom kiri: dot + garis
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: dotColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: dotColor, width: 2),
                  ),
                  child: Center(
                    child: Text('$urutan',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: dotColor)),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [dotColor.withValues(alpha: 0.5), Colors.transparent],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Konten stop
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE8EDF2)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nama + badge jenis
                  Row(
                    children: [
                      Expanded(
                        child: Text(nama,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: dotColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(dotIcon, size: 11, color: dotColor),
                            const SizedBox(width: 3),
                            Text(jenis.isNotEmpty ? jenis[0].toUpperCase() + jenis.substring(1) : 'Stop',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: dotColor)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (alamat.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(alamat,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],

                  // Muatan
                  if (koli > 0 || ecer > 0 || hv > 0) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (koli > 0)
                          _miniChip('$koli Koli', Icons.inventory_2_outlined, const Color(0xFF3B82F6)),
                        if (ecer > 0)
                          _miniChip('$ecer Ecer', Icons.shopping_basket_outlined, _orange),
                        if (hv > 0)
                          _miniChip('$hv HV', Icons.workspace_premium_outlined, _amber),
                      ],
                    ),
                  ],

                  // Foto e-POD
                  if (photo.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => onPhotoTap(photo),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: _orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _orange.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_camera_rounded, size: 15, color: _orange),
                            const SizedBox(width: 6),
                            Text('Lihat Bukti e-POD',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _orange)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

// ── Wave painter ──────────────────────────────────────────────────
class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _scaffoldBg;
    final path = Path();
    path.moveTo(0, size.height);
    path.quadraticBezierTo(size.width * 0.25, 0, size.width * 0.5, size.height * 0.5);
    path.quadraticBezierTo(size.width * 0.75, size.height, size.width, 0);
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => false;
}
