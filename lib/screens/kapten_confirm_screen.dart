import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_client.dart';

/// Layar "Konfirmasi Pengambilan" untuk kapten (seller implant).
///
/// Alur: kapten input muatan dulu (id_ritase NULL). Saat driver datang mengambil
/// barang, kapten memilih trip (ritase) yang datang, mengisi BERAPA yang diambil
/// (terisi otomatis = SISA saat ini, tinggal dikurangi), foto bukti (opsional),
/// dan catatan sisa (opsional) — lalu Konfirmasi.
/// Boleh dikonfirmasi berkali-kali (ambil bertahap); sisa = input − akumulasi.
/// Kolom "diambil" hanya menampilkan metrik yang sisanya > 0.
class KaptenConfirmScreen extends StatefulWidget {
  final String sellerName;

  const KaptenConfirmScreen({super.key, this.sellerName = ''});

  @override
  State<KaptenConfirmScreen> createState() => _KaptenConfirmScreenState();
}

class _KaptenConfirmScreenState extends State<KaptenConfirmScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _ritases = [];
  List<Map<String, dynamic>> _riwayat = [];
  List<Map<String, dynamic>> _sisaGrup = [];

  /// ritaseKe -> id_ritase yang dipilih di dropdown
  final Map<int, int> _selectedRitase = {};
  final Set<int> _confirming = {};

  /// groupKey ("jenis__rit") -> metric key -> controller jumlah diambil
  final Map<String, Map<String, TextEditingController>> _takenCtrls = {};
  /// groupKey -> catatan controller
  final Map<String, TextEditingController> _catatanCtrls = {};
  /// groupKey -> path foto serah terima (lokal, belum upload)
  final Map<String, String?> _handoverFoto = {};
  final Set<String> _uploadingFoto = {};
  /// groupKey -> key untuk scroll dari tombol "Penjemputan kedua"
  final Map<String, GlobalKey> _groupKeys = {};

  static const _takenSections = [
    {
      'title': 'AWB',
      'fields': [
        {'key': 'jumlah_awb', 'label': 'AWB'},
      ],
    },
    {
      'title': 'Koli',
      'fields': [
        {'key': 'koli_jkt', 'label': 'JKT'},
        {'key': 'koli_seg', 'label': 'SEG'},
        {'key': 'koli_btn', 'label': 'BTN'},
      ],
    },
    {
      'title': 'Eceran',
      'fields': [
        {'key': 'ecer_jkt', 'label': 'JKT'},
        {'key': 'ecer_seg', 'label': 'SEG'},
        {'key': 'ecer_btn', 'label': 'BTN'},
      ],
    },
    {
      'title': 'Koli High Value',
      'fields': [
        {'key': 'koli_hv_jkt', 'label': 'JKT'},
        {'key': 'koli_hv_seg', 'label': 'SEG'},
        {'key': 'koli_hv_btn', 'label': 'BTN'},
      ],
    },
    {
      'title': 'Eceran High Value',
      'fields': [
        {'key': 'ecer_hv_jkt', 'label': 'JKT'},
        {'key': 'ecer_hv_seg', 'label': 'SEG'},
        {'key': 'ecer_hv_btn', 'label': 'BTN'},
      ],
    },
  ];

  @override
  void dispose() {
    for (final m in _takenCtrls.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    for (final c in _catatanCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _toInt(dynamic v) => (v as num?)?.toInt() ?? 0;

  String _str(dynamic v) => (v ?? '').toString();

  int _clamp0(int v) => v < 0 ? 0 : v;

  String _groupKey(String jenis, int ritKe) => '${jenis}__$ritKe';

  /// Entri sisa grup (dari backend) berdasarkan jenis+rit.
  Map<String, dynamic>? _sisaEntry(String jenis, int ritKe) {
    for (final s in _sisaGrup) {
      if (_str(s['jenis_ritase']) == jenis && _toInt(s['ritase_ke']) == ritKe) return s;
    }
    return null;
  }

  /// Entri pending (input NULL) berdasarkan jenis+rit.
  Map<String, dynamic>? _pendingEntry(String jenis, int ritKe) {
    for (final p in _pending) {
      if (_str(p['jenis_ritase']) == jenis && _toInt(p['ritase_ke']) == ritKe) return p;
    }
    return null;
  }

  /// Nilai sisa per metrik untuk pre-fill & visibilitas.
  /// Prioritas: sisa backend → fallback total input pending.
  int _sisaMetric(String groupKey, String jenis, int ritKe, String metricKey) {
    final sisa = _sisaEntry(jenis, ritKe);
    if (sisa != null) {
      final sKey = metricKey == 'jumlah_awb' ? 'sisa_jumlah_awb' : 'sisa_$metricKey';
      if (sisa.containsKey(sKey)) return _clamp0(_toInt(sisa[sKey]));
    }
    final pending = _pendingEntry(jenis, ritKe);
    if (pending != null) {
      if (metricKey == 'jumlah_awb') return _clamp0(_toInt(pending['total_awb']));
      return _clamp0(_toInt(pending[metricKey]));
    }
    return 0;
  }

  /// Daftar grup form: gabungan grup pending + grup bersisa.
  /// Form tampil selama ada input NULL baru ATAU masih ada sisa.
  List<Map<String, dynamic>> _formGroups() {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    void add(String jenis, int ritKe) {
      final key = _groupKey(jenis, ritKe);
      if (key.isEmpty || seen.contains(key)) return;
      final pending = _pendingEntry(jenis, ritKe);
      final sisa = _sisaEntry(jenis, ritKe);
      final adaSisa = sisa != null &&
          (_toInt(sisa['sisa_awb']) > 0 ||
              _toInt(sisa['sisa_koli']) > 0 ||
              _toInt(sisa['sisa_ecer']) > 0 ||
              _toInt(sisa['sisa_hv']) > 0);
      if (pending == null && !adaSisa) return;
      seen.add(key);
      out.add({'key': key, 'jenis': jenis, 'ritKe': ritKe, 'pending': pending, 'sisa': sisa});
    }

    for (final p in _pending) {
      add(_str(p['jenis_ritase']), _toInt(p['ritase_ke']));
    }
    for (final s in _sisaGrup) {
      add(_str(s['jenis_ritase']), _toInt(s['ritase_ke']));
    }
    out.sort((a, b) {
      final c = (a['ritKe'] as int).compareTo(b['ritKe'] as int);
      if (c != 0) return c;
      return (a['jenis'] as String).compareTo(b['jenis'] as String);
    });
    return out;
  }

  String _fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final l = dt.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _photoFullUrl(String url) {
    if (url.startsWith('http')) return url;
    return '${ApiClient.baseUrl.replaceAll('/api/v1', '')}$url';
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiClient.fetchPendingConfirmations(),
        ApiClient.fetchKaptenRitase(),
        ApiClient.fetchKonfirmasiPenjemputan(),
      ]);
      if (!mounted) return;
      final pending = results[0] as List<Map<String, dynamic>>;
      final riwayatData = results[2] as Map<String, dynamic>?;
      final List<Map<String, dynamic>> sisaGrup = [];
      final List<Map<String, dynamic>> riwayat = [];
      if (riwayatData != null) {
        final rw = riwayatData['riwayat'];
        if (rw is List) riwayat.addAll(List<Map<String, dynamic>>.from(rw));
        final sg = riwayatData['sisa_grup'];
        if (sg is List) sisaGrup.addAll(List<Map<String, dynamic>>.from(sg));
      }
      // Reset + pre-fill controller diambil dari SISA (bukan total pending).
      for (final m in _takenCtrls.values) {
        for (final c in m.values) {
          c.dispose();
        }
      }
      _takenCtrls.clear();
      _groupKeys.clear();
      setState(() {
        _pending = pending;
        _ritases = results[1] as List<Map<String, dynamic>>;
        // Urutkan riwayat: Rit 1, 2, 3 — terbaru dulu di dalam rit yang sama.
        riwayat.sort((a, b) {
          final c = _toInt(a['ritase_ke']).compareTo(_toInt(b['ritase_ke']));
          if (c != 0) return c;
          return _str(b['created_at']).compareTo(_str(a['created_at']));
        });
        _riwayat = riwayat;
        _sisaGrup = sisaGrup;
        _isLoading = false;
      });
      // Prefill setelah state terisi (butuh _sisaGrup).
      for (final g in _formGroups()) {
        final key = g['key'] as String;
        final jenis = g['jenis'] as String;
        final ritKe = g['ritKe'] as int;
        final map = <String, TextEditingController>{};
        for (final section in _takenSections) {
          for (final f in (section['fields'] as List)) {
            final mkey = (f as Map)['key'] as String;
            map[mkey] = TextEditingController(text: '${_sisaMetric(key, jenis, ritKe, mkey)}');
          }
        }
        _takenCtrls[key] = map;
        _catatanCtrls.putIfAbsent(key, () => TextEditingController());
        _groupKeys.putIfAbsent(key, () => GlobalKey());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat data: $e';
        _isLoading = false;
      });
    }
  }

  /// Kandidat trip untuk satu grup (ritase_ke + jenis harus cocok).
  List<Map<String, dynamic>> _candidatesFor(String jenis, int ritKe) {
    return _ritases.where((r) {
      if (_toInt(r['ritase_ke']) != ritKe) return false;
      final rJenis = _str(r['jenis_ritase']);
      if (jenis.isNotEmpty && rJenis.isNotEmpty && rJenis != jenis) return false;
      return true;
    }).toList();
  }

  String _ritaseShortLabel(Map<String, dynamic> r) {
    final driver = _str(r['nama_driver']);
    final ritKe = _toInt(r['ritase_ke']);
    final nama = driver.isNotEmpty ? driver : 'Driver';
    return ritKe > 0 ? '$nama • Rit $ritKe' : nama;
  }

  /// Pangkas "HH:MM:SS" → "HH:MM" agar label ringkas.
  String _shortTime(String t) {
    final m = RegExp(r'^(\d{1,2}:\d{2})').firstMatch(t.trim());
    return m != null ? m.group(1)! : t;
  }

  /// Isi ulang kolom diambil = sisa saat ini ("Ambil semua").
  void _refillTaken(String key, String jenis, int ritKe) {
    final ctrls = _takenCtrls[key];
    if (ctrls == null) return;
    setState(() {
      for (final section in _takenSections) {
        for (final f in (section['fields'] as List)) {
          final mkey = (f as Map)['key'] as String;
          ctrls[mkey]?.text = '${_sisaMetric(key, jenis, ritKe, mkey)}';
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diisi = sisa saat ini.')),
    );
  }

  Future<void> _pickHandoverFoto(String key) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
      );
      if (picked != null && mounted) {
        setState(() => _handoverFoto[key] = picked.path);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal ambil foto: $e')),
      );
    }
  }

  int _takenInt(String key, String metric) {
    final t = _takenCtrls[key]?[metric]?.text ?? '0';
    final v = int.tryParse(t) ?? 0;
    return v < 0 ? 0 : v;
  }

  Future<void> _confirm(String key, String jenis, int ritKe) async {
    final idRitase = _selectedRitase[ritKe];
    if (idRitase == null || _confirming.contains(ritKe)) return;
    setState(() => _confirming.add(ritKe));
    try {
      // Upload foto serah terima dulu (opsional — gagal upload tidak menghalangi).
      String? fotoUrl;
      final fotoPath = _handoverFoto[key];
      if (fotoPath != null && fotoPath.isNotEmpty) {
        setState(() => _uploadingFoto.add(key));
        try {
          fotoUrl = await ApiClient.uploadManifestPhoto(
            idRitase: 0,
            filePath: fotoPath,
            namaLokasi: widget.sellerName,
          );
        } finally {
          if (mounted) setState(() => _uploadingFoto.remove(key));
        }
      }

      final result = await ApiClient.confirmPickup(
        jenisRitase: jenis.isEmpty ? 'outgoing' : jenis,
        ritaseKe: ritKe,
        idRitase: idRitase,
        jumlahAwb: _takenInt(key, 'jumlah_awb'),
        koliJkt: _takenInt(key, 'koli_jkt'),
        koliSeg: _takenInt(key, 'koli_seg'),
        koliBtn: _takenInt(key, 'koli_btn'),
        ecerJkt: _takenInt(key, 'ecer_jkt'),
        ecerSeg: _takenInt(key, 'ecer_seg'),
        ecerBtn: _takenInt(key, 'ecer_btn'),
        koliHvJkt: _takenInt(key, 'koli_hv_jkt'),
        koliHvSeg: _takenInt(key, 'koli_hv_seg'),
        koliHvBtn: _takenInt(key, 'koli_hv_btn'),
        ecerHvJkt: _takenInt(key, 'ecer_hv_jkt'),
        ecerHvSeg: _takenInt(key, 'ecer_hv_seg'),
        ecerHvBtn: _takenInt(key, 'ecer_hv_btn'),
        fotoPenjemputanUrl: fotoUrl,
        catatan: _catatanCtrls[key]?.text.trim(),
      );
      if (!mounted) return;
      if (result != null) {
        final sisa = result['sisa'] as Map<String, dynamic>?;
        final sKoli = _toInt(sisa?['total_koli']);
        final sEcer = _toInt(sisa?['total_ecer']);
        final sHv = _toInt(sisa?['total_hv']);
        final sAwb = _toInt(sisa?['jumlah_awb']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tersimpan! Sisa — $sAwb AWB, $sKoli koli, $sEcer ecer, $sHv HV.'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
        _selectedRitase.remove(ritKe);
        _handoverFoto.remove(key);
        _catatanCtrls[key]?.clear();
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Konfirmasi gagal, coba lagi.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal konfirmasi: $e')),
      );
    } finally {
      if (mounted) setState(() => _confirming.remove(ritKe));
    }
  }

  Map<String, dynamic>? _sisaFor(String jenis, int ritKe) => _sisaEntry(jenis, ritKe);

  /// Kata urutan Indonesia untuk status penjemputan (1-10), selebihnya angka.
  static const _urutanWords = {
    1: 'pertama',
    2: 'kedua',
    3: 'ketiga',
    4: 'keempat',
    5: 'kelima',
    6: 'keenam',
    7: 'ketujuh',
    8: 'kedelapan',
    9: 'kesembilan',
    10: 'kesepuluh',
  };

  String _urutanWord(int n) => _urutanWords[n] ?? 'ke-$n';

  /// Nomor urut tiap baris riwayat dalam grupnya (dari yang paling awal),
  /// id baris terakhir tiap grup, dan jumlah baris tiap grup.
  /// Key grup: "jenis__rit".
  Map<String, dynamic> _riwayatOrder() {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in _riwayat) {
      final k = '${_str(r['jenis_ritase'])}__${_toInt(r['ritase_ke'])}';
      groups.putIfAbsent(k, () => []).add(r);
    }
    final seqById = <int, int>{};
    final latestIdByGroup = <String, int>{};
    final countByGroup = <String, int>{};
    for (final e in groups.entries) {
      e.value.sort((a, b) {
        final c = _str(a['created_at']).compareTo(_str(b['created_at']));
        if (c != 0) return c;
        return _toInt(a['id']).compareTo(_toInt(b['id']));
      });
      countByGroup[e.key] = e.value.length;
      for (var i = 0; i < e.value.length; i++) {
        final id = _toInt(e.value[i]['id']);
        seqById[id] = i + 1;
        if (i == e.value.length - 1) latestIdByGroup[e.key] = id;
      }
    }
    return {
      'seqById': seqById,
      'latestIdByGroup': latestIdByGroup,
      'countByGroup': countByGroup,
    };
  }

  /// Scroll ke form grup (untuk tombol "Penjemputan kedua").
  void _scrollToGroup(String key) {
    final ctx = _groupKeys[key]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400));
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _isLoading || _error != null ? <Map<String, dynamic>>[] : _formGroups();
    final order = _riwayatOrder();
    final seqById = order['seqById'] as Map<int, int>;
    final latestIdByGroup = order['latestIdByGroup'] as Map<String, int>;
    final countByGroup = order['countByGroup'] as Map<String, int>;
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Konfirmasi Pengambilan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (widget.sellerName.isNotEmpty)
              Text(
                widget.sellerName,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0D47A1)))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _load, child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (groups.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.check_circle_outline_rounded, size: 48, color: Color(0xFF16A34A)),
                                SizedBox(height: 8),
                                Text(
                                  'Tidak ada sisa maupun input baru',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                ),
                              ],
                            ),
                          )
                        else
                          ...groups.map(_buildGroupCard),
                        if (_riwayat.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Serah Terima Hari Ini',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                          const SizedBox(height: 8),
                          ..._riwayat.map((item) {
                            final key =
                                '${_str(item['jenis_ritase'])}__${_toInt(item['ritase_ke'])}';
                            final id = _toInt(item['id']);
                            return _buildRiwayatCard(
                              item,
                              seqById[id] ?? 1,
                              latestIdByGroup[key] == id,
                              (countByGroup[key] ?? 0) + 1,
                            );
                          }),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> g) {
    final key = g['key'] as String;
    final jenis = g['jenis'] as String;
    final ritKe = g['ritKe'] as int;
    final pending = g['pending'] as Map<String, dynamic>?;
    final sisa = g['sisa'] as Map<String, dynamic>?;
    final count = pending != null ? _toInt(pending['jumlah_input']) : 0;
    final sAwb = _toInt(sisa?['sisa_awb']);
    final sKoli = _toInt(sisa?['sisa_koli']);
    final sEcer = _toInt(sisa?['sisa_ecer']);
    final sHv = _toInt(sisa?['sisa_hv']);
    final candidates = _candidatesFor(jenis, ritKe);
    final selected = _selectedRitase[ritKe];
    final busy = _confirming.contains(ritKe);
    final fotoPath = _handoverFoto[key];
    final uploading = _uploadingFoto.contains(key);
    // Seksi diambil yang terlihat: hanya metrik dengan sisa > 0.
    final visibleSections = _takenSections.where((section) {
      final fields = (section['fields'] as List).cast<Map<String, String>>();
      return fields.any((f) => _sisaMetric(key, jenis, ritKe, f['key']!) > 0);
    }).toList();

    return Container(
      key: _groupKeys.putIfAbsent(key, () => GlobalKey()),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D47A1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Rit $ritKe',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pending != null
                      ? '$count input belum terkonfirmasi'
                      : 'Sisa dari pengambilan sebelumnya',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _statChip('Sisa: $sAwb AWB'),
              _statChip('$sKoli Koli'),
              _statChip('$sEcer Ecer'),
              _statChip('$sHv HV'),
            ],
          ),
          const SizedBox(height: 12),
          if (candidates.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF9C3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE047)),
              ),
              child: const Text(
                'Belum ada jadwal driver untuk Rit ini — menunggu admin generate.',
                style: TextStyle(fontSize: 12, color: Color(0xFF854D0E)),
              ),
            )
          else ...[
            const Text(
              'Driver yang datang mengambil:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: selected,
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              hint: const Text('Pilih driver...', style: TextStyle(fontSize: 13)),
              items: candidates.map((r) {
                final id = _toInt(r['id_ritase']);
                final driver = _str(r['nama_driver']).isEmpty ? 'Driver' : _str(r['nama_driver']);
                final rKe = _toInt(r['ritase_ke']);
                final kode = _str(r['kode_ritase']);
                final jamMulai = _shortTime(_str(r['jam_mulai']));
                final jamSelesai = _shortTime(_str(r['jam_selesai']));
                final plat = _str(r['plat_nomor']);
                final jam = (jamMulai.isNotEmpty && jamSelesai.isNotEmpty) ? ' • $jamMulai-$jamSelesai' : '';
                final nopol = plat.isNotEmpty && plat != '-' ? ' • $plat' : '';
                return DropdownMenuItem<int>(
                  value: id,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        rKe > 0 ? '$driver • Rit $rKe' : driver,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (kode.isNotEmpty || jam.isNotEmpty || nopol.isNotEmpty)
                        Text(
                          '$kode$jam$nopol',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                );
              }).toList(),
              selectedItemBuilder: (context) {
                return candidates.map((r) {
                  return Text(
                    _ritaseShortLabel(r),
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  );
                }).toList();
              },
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                        if (v != null) _selectedRitase[ritKe] = v;
                      }),
            ),
            const SizedBox(height: 12),
            if (visibleSections.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Text(
                  'Tidak ada sisa barang — semua sudah diambil driver.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF15803D)),
                ),
              )
            else ...[
              Row(
                children: [
                  const Text(
                    'Jumlah yang diambil driver:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: busy ? null : () => _refillTaken(key, jenis, ritKe),
                    icon: const Icon(Icons.checklist_rounded, size: 16),
                    label: const Text('Ambil semua', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              const Text(
                'Terisi otomatis = sisa saat ini. Hanya kolom yang bersisa yang tampil.',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 6),
              ...visibleSections.map((section) => _buildTakenSection(
                    key,
                    (section['title'] as String?) ?? '',
                    ((section['fields'] as List?) ?? []).cast<Map<String, String>>(),
                    busy,
                  )),
            ],
            const SizedBox(height: 8),
            // Foto bukti serah terima (opsional)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (busy || uploading) ? null : () => _pickHandoverFoto(key),
                    icon: const Icon(Icons.camera_alt_rounded, size: 16),
                    label: Text(
                      fotoPath != null ? 'Ganti Foto' : 'Foto Bukti (opsional)',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                if (fotoPath != null) ...[
                  const SizedBox(width: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(fotoPath),
                      width: 56, height: 56, fit: BoxFit.cover,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // Catatan sisa (opsional)
            TextField(
              controller: _catatanCtrls[key],
              enabled: !busy,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Catatan sisa, mis: 40 koli tidak muat...',
                hintStyle: const TextStyle(fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: (selected == null || busy) ? null : () => _confirm(key, jenis, ritKe),
                icon: busy
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, color: Colors.white),
                label: Text(
                  busy ? 'Menyimpan...' : 'Konfirmasi Driver',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTakenSection(String groupKey, String title, List<Map<String, String>> fields, bool busy) {
    // Tampilkan hanya field yang sisanya > 0.
    final visible = fields.where((f) {
      final parts = groupKey.split('__');
      final jenis = parts.isNotEmpty ? parts[0] : '';
      final ritKe = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      return _sisaMetric(groupKey, jenis, ritKe, f['key']!) > 0;
    }).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0D47A1)),
          ),
          const SizedBox(height: 4),
          Row(
            children: visible.map((f) {
              final mkey = f['key']!;
              final label = f['label']!;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: f == visible.last ? 0 : 8),
                  child: TextField(
                    controller: _takenCtrls[groupKey]?[mkey],
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: label,
                      labelStyle: const TextStyle(fontSize: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Kartu riwayat serah terima.
  /// [seq] = nomor urut dalam grup (1 = pertama). [isLatest] = baris terbaru
  /// grupnya — hanya di sinilah tombol penjemputan berikutnya tampil (bila
  /// masih bersisa), berlabel [nextNum] ("kedua", "ketiga", ...).
  Widget _buildRiwayatCard(Map<String, dynamic> item, int seq, bool isLatest, int nextNum) {
    final jenis = _str(item['jenis_ritase']);
    final ritKe = _toInt(item['ritase_ke']);
    final key = _groupKey(jenis, ritKe);
    final driver = _str(item['nama_driver']);
    final kode = _str(item['kode_ritase']);
    final waktu = _fmtTime(_str(item['created_at']));
    final awb = _toInt(item['jumlah_awb']);
    final koli = _toInt(item['total_koli']);
    final ecer = _toInt(item['total_ecer']);
    final hv = _toInt(item['total_hv']);
    final foto = _str(item['foto_penjemputan_url']);
    final catatan = _str(item['catatan']);
    final sisa = _sisaFor(jenis, ritKe);
    final sisaKoli = _toInt(sisa?['sisa_koli']);
    final sisaEcer = _toInt(sisa?['sisa_ecer']);
    final sisaHv = _toInt(sisa?['sisa_hv']);
    final sisaAwb = _toInt(sisa?['sisa_awb']);
    final adaSisa = sisaKoli > 0 || sisaEcer > 0 || sisaHv > 0 || sisaAwb > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${driver.isEmpty ? 'Driver' : driver} • Rit $ritKe',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ),
              if (waktu.isNotEmpty)
                Text(waktu, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontFamily: 'monospace')),
            ],
          ),
          if (kode.isNotEmpty)
            Text(kode, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Text(
              'Penjemputan ${_urutanWord(seq)}',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF1D4ED8)),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _statChip('Diambil: $awb AWB'),
              _statChip('$koli koli'),
              _statChip('$ecer ecer'),
              _statChip('$hv HV'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: adaSisa ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: adaSisa ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0),
                  ),
                ),
                child: Text(
                  adaSisa
                      ? 'Sisa: $sisaAwb AWB, $sisaKoli koli, $sisaEcer ecer, $sisaHv HV'
                      : 'Habis terambil',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: adaSisa ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                  ),
                ),
              ),
            ],
          ),
          if (catatan.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '📝 $catatan',
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF475569)),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (foto.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _showFotoDialog(foto),
                  icon: const Icon(Icons.photo_rounded, size: 16),
                  label: const Text('Lihat Foto Bukti', style: TextStyle(fontSize: 12)),
                ),
              if (foto.isNotEmpty && adaSisa && isLatest) const SizedBox(width: 8),
              // Tombol penjemputan berikutnya: hanya di kartu TERAKHIR tiap grup
              // dan hanya bila grup masih bersisa. Label mengikuti nomor berikut.
              if (adaSisa && isLatest)
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _scrollToGroup(key),
                    icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                    label: Text(
                      'Penjemputan ${_urutanWord(nextNum)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showFotoDialog(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.network(
                _photoFullUrl(url),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Foto tidak dapat dimuat.'),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
      ),
    );
  }
}
