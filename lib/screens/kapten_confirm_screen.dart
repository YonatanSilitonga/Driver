import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_client.dart';

/// Layar "Konfirmasi Pengambilan" untuk kapten.
///
/// Menampilkan SEMUA implant kapten. Tiap implant punya card sendiri dan bisa
/// dicentang untuk ikut dijemput. Satu grup (jenis + Rit) memakai satu driver,
/// satu foto/catatan, dan satu transaksi konfirmasi untuk semua card tercentang.
class KaptenConfirmScreen extends StatefulWidget {
  final String implantName;

  const KaptenConfirmScreen({super.key, this.implantName = ''});

  @override
  State<KaptenConfirmScreen> createState() => _KaptenConfirmScreenState();
}

class _KaptenConfirmScreenState extends State<KaptenConfirmScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _implants = [];
  List<Map<String, dynamic>> _history = [];
  bool _historyLoading = true;
  String? _historyError;
  String _historyFilter = 'week';
  int? _historyImplant;
  int _tabIndex = 0;

  /// groupKey -> kandidat ritase yang menyinggahi semua implant tercentang
  final Map<String, List<Map<String, dynamic>>> _candidates = {};
  final Map<String, bool> _loadingCandidates = {};
  final Map<String, int> _candidateSeq = {};
  final Map<String, int> _selectedRitase = {};
  final Map<String, Set<int>> _checked = {};
  final Set<String> _confirming = {};

  /// "$implantId__$groupKey" -> metric -> controller
  final Map<String, Map<String, TextEditingController>> _takenCtrls = {};

  final Map<String, TextEditingController> _catatanCtrls = {};
  final Map<String, String?> _handoverFoto = {};
  final Set<String> _uploadingFoto = {};
  final Map<String, GlobalKey> _groupKeys = {};
  final Map<String, GlobalKey> _implantKeys = {};

  static const _takenSections = [
    {
      'title': 'AWB',
      'color': 0xFF6D28D9,
      'fields': [
        {'key': 'jumlah_awb', 'label': 'AWB'},
      ],
    },
    {
      'title': 'Koli',
      'color': 0xFF1E40AF,
      'fields': [
        {'key': 'koli_jkt', 'label': 'JKT'},
        {'key': 'koli_seg', 'label': 'SEG'},
        {'key': 'koli_btn', 'label': 'BTN'},
      ],
    },
    {
      'title': 'Eceran',
      'color': 0xFF16A34A,
      'fields': [
        {'key': 'ecer_jkt', 'label': 'JKT'},
        {'key': 'ecer_seg', 'label': 'SEG'},
        {'key': 'ecer_btn', 'label': 'BTN'},
      ],
    },
    {
      'title': 'AWB High Value',
      'color': 0xFFB91C1C,
      'fields': [
        {'key': 'awb_hv_jkt', 'label': 'JKT'},
        {'key': 'awb_hv_seg', 'label': 'SEG'},
        {'key': 'awb_hv_btn', 'label': 'BTN'},
      ],
    },
    {
      'title': 'Koli High Value',
      'color': 0xFFF59E0B,
      'fields': [
        {'key': 'koli_hv_jkt', 'label': 'JKT'},
        {'key': 'koli_hv_seg', 'label': 'SEG'},
        {'key': 'koli_hv_btn', 'label': 'BTN'},
      ],
    },
    {
      'title': 'Ecer High Value',
      'color': 0xFFEA580C,
      'fields': [
        {'key': 'ecer_hv_jkt', 'label': 'JKT'},
        {'key': 'ecer_hv_seg', 'label': 'SEG'},
        {'key': 'ecer_hv_btn', 'label': 'BTN'},
      ],
    },
  ];

  @override
  void dispose() {
    _disposeCtrls();
    super.dispose();
  }

  void _disposeCtrls() {
    for (final m in _takenCtrls.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    for (final c in _catatanCtrls.values) {
      c.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _toInt(dynamic v) => (v as num?)?.toInt() ?? 0;

  String _str(dynamic v) => (v ?? '').toString();

  int _clamp0(int v) => v < 0 ? 0 : v;

  String _prefillText(int v) => v > 0 ? '$v' : '';

  String _groupKey(String jenis, int ritKe) => '${jenis}__$ritKe';

  String _ctrlKey(int implantId, String groupKey) => '${implantId}__$groupKey';

  int _pointOf(Map<String, dynamic> imp) {
    final id = _toInt(imp['id_titik_implant']);
    return id > 0 ? id : _toInt(imp['id_implant']);
  }

  String _pointNameOf(Map<String, dynamic> imp) {
    final name = _str(imp['nama_titik_implant']);
    return name.isNotEmpty ? name : _str(imp['nama_implant']);
  }

  Map<String, dynamic>? _implantOf(int id) {
    for (final m in _implants) {
      if (_toInt(m['id_implant']) == id) return m;
    }
    return null;
  }

  List<Map<String, dynamic>> _pendingOf(int id) {
    final p = _implantOf(id)?['pending'];
    if (p is List) return List<Map<String, dynamic>>.from(p);
    return [];
  }

  List<Map<String, dynamic>> _sisaGrupOf(int id) {
    final s = _implantOf(id)?['sisa_grup'];
    if (s is List) return List<Map<String, dynamic>>.from(s);
    return [];
  }

  Map<String, dynamic>? _pendingEntry(int id, String jenis, int ritKe) {
    for (final p in _pendingOf(id)) {
      if (_str(p['jenis_ritase']) == jenis && _toInt(p['ritase_ke']) == ritKe) {
        return p;
      }
    }
    return null;
  }

  Map<String, dynamic>? _sisaEntry(int id, String jenis, int ritKe) {
    for (final s in _sisaGrupOf(id)) {
      if (_str(s['jenis_ritase']) == jenis && _toInt(s['ritase_ke']) == ritKe) {
        return s;
      }
    }
    return null;
  }

  int _sisaMetric(int id, String jenis, int ritKe, String metricKey) {
    final sisa = _sisaEntry(id, jenis, ritKe);
    if (sisa != null) {
      final sKey = metricKey == 'jumlah_awb'
          ? 'sisa_jumlah_awb'
          : 'sisa_$metricKey';
      if (sisa.containsKey(sKey)) return _clamp0(_toInt(sisa[sKey]));
      if (metricKey == 'awb_hv_jkt' && sisa.containsKey('sisa_awb_hv')) {
        return _clamp0(_toInt(sisa['sisa_awb_hv']));
      }
      if (metricKey == 'koli_hv_jkt' && sisa.containsKey('sisa_koli_hv')) {
        return _clamp0(_toInt(sisa['sisa_koli_hv']));
      }
      if (metricKey == 'ecer_hv_jkt' &&
          (sisa.containsKey('sisa_hv_awb') ||
              sisa.containsKey('sisa_ecer_hv'))) {
        return _clamp0(
          _toInt(sisa['sisa_hv_awb']) + _toInt(sisa['sisa_ecer_hv']),
        );
      }
    }
    final pending = _pendingEntry(id, jenis, ritKe);
    if (pending != null) {
      if (metricKey == 'jumlah_awb') {
        return _clamp0(_toInt(pending['total_awb']));
      }
      return _clamp0(_toInt(pending[metricKey]));
    }
    return 0;
  }

  int _groupTotal(int id, Map<String, dynamic> g, String metric) {
    final sisa = _sisaEntry(id, g['jenis'] as String, g['ritKe'] as int);
    return _clamp0(_toInt(sisa?['sisa_$metric']));
  }

  bool _implantHasContent(int id, String jenis, int ritKe) {
    if (_pendingEntry(id, jenis, ritKe) != null) return true;
    final sisa = _sisaEntry(id, jenis, ritKe);
    if (sisa == null) return false;
    if (_str(sisa['status_grup']) == 'selesai') return false;
    return _toInt(sisa['sisa_awb']) > 0 ||
        _toInt(sisa['sisa_koli']) > 0 ||
        _toInt(sisa['sisa_ecer']) > 0 ||
        _toInt(sisa['sisa_hv']) > 0;
  }

  List<Map<String, dynamic>> _formGroups() {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    void add(
      Map<String, dynamic> imp,
      String jenis,
      int ritKe,
      String tanggal,
    ) {
      final id = _toInt(imp['id_implant']);
      if (jenis.isEmpty && ritKe == 0) return;
      if (!_implantHasContent(id, jenis, ritKe)) return;
      final key = _groupKey(jenis, ritKe);
      if (seen.contains(key)) return;
      seen.add(key);
      out.add({
        'key': key,
        'jenis': jenis,
        'ritKe': ritKe,
        'tanggalAsal': tanggal,
      });
    }

    for (final imp in _implants) {
      final id = _toInt(imp['id_implant']);
      for (final p in _pendingOf(id)) {
        add(
          imp,
          _str(p['jenis_ritase']),
          _toInt(p['ritase_ke']),
          _str(p['tanggal_input']),
        );
      }
      for (final s in _sisaGrupOf(id)) {
        add(imp, _str(s['jenis_ritase']), _toInt(s['ritase_ke']), '');
      }
    }
    out.sort((a, b) {
      final c = (a['ritKe'] as int).compareTo(b['ritKe'] as int);
      if (c != 0) return c;
      return (a['jenis'] as String).compareTo(b['jenis'] as String);
    });
    return out;
  }

  List<Map<String, dynamic>> _groupImplants(Map<String, dynamic> g) {
    final jenis = g['jenis'] as String;
    final ritKe = g['ritKe'] as int;
    final out = <Map<String, dynamic>>[];
    for (final imp in _implants) {
      final id = _toInt(imp['id_implant']);
      if (_implantHasContent(id, jenis, ritKe)) {
        out.add({
          'id_implant': id,
          'id_titik_implant': _toInt(imp['id_titik_implant']),
          'nama_implant': _str(imp['nama_implant']),
          'nama_titik_implant': _pointNameOf(imp),
        });
      }
    }
    return out;
  }

  Set<int> _checkedIds(String key) => _checked[key] ?? <int>{};

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
      final implants = await ApiClient.fetchBatchOverview();
      if (!mounted) return;
      _disposeCtrls();
      _takenCtrls.clear();
      _catatanCtrls.clear();
      _candidates.clear();
      _candidateSeq.clear();
      _selectedRitase.clear();
      _checked.clear();
      _handoverFoto.clear();
      _uploadingFoto.clear();
      _groupKeys.clear();
      _implantKeys.clear();

      setState(() {
        _implants = implants;
        _isLoading = false;
      });

      final groups = _formGroups();
      for (final g in groups) {
        final key = g['key'] as String;
        final jenis = g['jenis'] as String;
        final ritKe = g['ritKe'] as int;
        _catatanCtrls[key] = TextEditingController();
        _groupKeys.putIfAbsent(key, () => GlobalKey());
        final ids = <int>{};
        for (final imp in _groupImplants(g)) {
          final id = _toInt(imp['id_implant']);
          ids.add(id);
          final ck = _ctrlKey(id, key);
          final map = <String, TextEditingController>{};
          for (final section in _takenSections) {
            for (final f in (section['fields'] as List)) {
              final mkey = (f as Map)['key'] as String;
              final c = TextEditingController(
                text: _prefillText(_sisaMetric(id, jenis, ritKe, mkey)),
              );
              c.addListener(_onTakenChanged);
              map[mkey] = c;
            }
          }
          _takenCtrls[ck] = map;
          _implantKeys.putIfAbsent(ck, () => GlobalKey());
        }
        _checked[key] = ids;
      }
      await Future.wait(groups.map(_loadCandidates));
      _loadHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadHistory({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _historyLoading = true);
    try {
      final list = await ApiClient.fetchKaptenKonfirmasiHistory(
        filter: _historyFilter,
        idImplant: _historyImplant,
      );
      if (!mounted) return;
      setState(() {
        _history = list;
        _historyLoading = false;
        _historyError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyLoading = false;
        _historyError = 'Gagal memuat riwayat: $e';
      });
    }
  }

  Future<void> _loadCandidates(Map<String, dynamic> g) async {
    final key = g['key'] as String;
    final seq = (_candidateSeq[key] ?? 0) + 1;
    _candidateSeq[key] = seq;
    final ids = _checkedIds(key).toList();
    if (ids.isEmpty) {
      if (mounted) {
        setState(() {
          _candidates[key] = [];
          _selectedRitase.remove(key);
          _loadingCandidates[key] = false;
        });
      }
      return;
    }
    setState(() => _loadingCandidates[key] = true);
    try {
      final jenis = g['jenis'] as String;
      final ritKe = g['ritKe'] as int;
      final pointIds = <int>{};
      for (final imp in _groupImplants(g)) {
        final id = _toInt(imp['id_implant']);
        if (ids.contains(id)) pointIds.add(_pointOf(imp));
      }
      if (pointIds.isEmpty) {
        if (!mounted || _candidateSeq[key] != seq) return;
        setState(() {
          _candidates[key] = [];
          _selectedRitase.remove(key);
          _loadingCandidates[key] = false;
        });
        return;
      }
      final lists = await Future.wait(
        pointIds.map(
          (pointId) => ApiClient.fetchBatchRitase(ids, titikId: pointId),
        ),
      );
      bool matchesGroup(Map<String, dynamic> r) {
        if (_toInt(r['ritase_ke']) != ritKe) return false;
        final rJenis = _str(r['jenis_ritase']);
        return jenis.isEmpty || rJenis.isEmpty || rJenis == jenis;
      }

      final filtered = lists
          .map((list) => list.where(matchesGroup).toList())
          .toList();
      final counts = <int, int>{};
      for (final list in filtered) {
        final seen = <int>{};
        for (final r in list) {
          final id = _toInt(r['id_ritase']);
          if (id > 0 && seen.add(id)) {
            counts[id] = (counts[id] ?? 0) + 1;
          }
        }
      }
      final list = <Map<String, dynamic>>[];
      final seenIds = <int>{};
      for (final r in filtered.first) {
        final id = _toInt(r['id_ritase']);
        if (id > 0 && counts[id] == filtered.length && seenIds.add(id)) {
          list.add(r);
        }
      }
      if (!mounted || _candidateSeq[key] != seq) return;
      setState(() {
        _candidates[key] = list;
        final cur = _selectedRitase[key];
        if (cur == null || !list.any((r) => _toInt(r['id_ritase']) == cur)) {
          _selectedRitase.remove(key);
        }
        _loadingCandidates[key] = false;
      });
    } catch (_) {
      if (!mounted || _candidateSeq[key] != seq) return;
      setState(() {
        _candidates[key] = [];
        _selectedRitase.remove(key);
        _loadingCandidates[key] = false;
      });
    }
  }

  void _toggleImplant(Map<String, dynamic> g, int implantId, bool checked) {
    final key = g['key'] as String;
    final set = _checked.putIfAbsent(key, () => <int>{});
    if (checked) {
      set.add(implantId);
      final ck = _ctrlKey(implantId, key);
      if (!_takenCtrls.containsKey(ck)) {
        final jenis = g['jenis'] as String;
        final ritKe = g['ritKe'] as int;
        final map = <String, TextEditingController>{};
        for (final section in _takenSections) {
          for (final f in (section['fields'] as List)) {
            final mkey = (f as Map)['key'] as String;
            final c = TextEditingController(
              text: _prefillText(_sisaMetric(implantId, jenis, ritKe, mkey)),
            );
            c.addListener(_onTakenChanged);
            map[mkey] = c;
          }
        }
        _takenCtrls[ck] = map;
        _implantKeys.putIfAbsent(ck, () => GlobalKey());
      }
    } else {
      set.remove(implantId);
    }
    setState(() {});
    _loadCandidates(g);
  }

  String _ritaseShortLabel(Map<String, dynamic> r) {
    final driver = _str(r['nama_driver']);
    final ritKe = _toInt(r['ritase_ke']);
    final nama = driver.isNotEmpty ? driver : 'Driver';
    return ritKe > 0 ? '$nama \u2022 Rit $ritKe' : nama;
  }

  String _shortTime(String t) {
    final m = RegExp(r'^(\d{1,2}:\d{2})').firstMatch(t.trim());
    return m != null ? m.group(1)! : t;
  }

  String _tanggalLabel(String tgl) {
    if (tgl.isEmpty) return '';
    final d = DateTime.tryParse(tgl);
    if (d == null) return '';
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '';
    }
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return ' \u2022 $dd/$mm';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal ambil foto: $e')));
    }
  }

  int _takenInt(String ctrlKey, String metric) {
    final t = _takenCtrls[ctrlKey]?[metric]?.text ?? '0';
    final v = int.tryParse(t) ?? 0;
    return v < 0 ? 0 : v;
  }

  int _takenTotal(int implantId, String key) {
    final ck = _ctrlKey(implantId, key);
    final ctrls = _takenCtrls[ck];
    if (ctrls == null) return 0;
    var sum = 0;
    for (final mkey in ctrls.keys) {
      sum += _takenInt(ck, mkey);
    }
    return sum;
  }

  bool _canConfirm(String key) {
    if (_selectedRitase[key] == null) return false;
    for (final id in _checkedIds(key)) {
      if (_takenTotal(id, key) > 0) return true;
    }
    return false;
  }

  void _onTakenChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _confirm(Map<String, dynamic> g) async {
    final key = g['key'] as String;
    final jenis = g['jenis'] as String;
    final ritKe = g['ritKe'] as int;
    final tanggalAsal = _str(g['tanggalAsal']);
    final idRitase = _selectedRitase[key];
    if (idRitase == null || _confirming.contains(key)) return;

    final items = <Map<String, dynamic>>[];
    for (final id in _checkedIds(key)) {
      final ck = _ctrlKey(id, key);
      var total = 0;
      final m = <String, dynamic>{'id_implant': id};
      for (final section in _takenSections) {
        for (final f in (section['fields'] as List)) {
          final mkey = (f as Map)['key'] as String;
          final v = _takenInt(ck, mkey);
          total += v;
          final payloadKey = mkey == 'jumlah_awb' ? 'awb' : mkey;
          m['diambil_$payloadKey'] = v;
        }
      }
      if (total > 0) items.add(m);
    }

    if (items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Minimal isi salah satu jumlah yang diambil driver'),
          ),
        );
      }
      return;
    }

    setState(() => _confirming.add(key));
    try {
      String? fotoUrl;
      final fotoPath = _handoverFoto[key];
      if (fotoPath != null && fotoPath.isNotEmpty) {
        setState(() => _uploadingFoto.add(key));
        try {
          fotoUrl = await ApiClient.uploadManifestPhoto(
            idRitase: 0,
            filePath: fotoPath,
            namaLokasi: widget.implantName.isNotEmpty
                ? widget.implantName
                : 'Gabungan',
          );
        } catch (_) {
        } finally {
          if (mounted) setState(() => _uploadingFoto.remove(key));
        }
      }

      final result = await ApiClient.confirmPickupBatch(
        jenisRitase: jenis.isEmpty ? 'outgoing' : jenis,
        ritaseKe: ritKe,
        ritaseKeAsal: ritKe,
        tanggalAsal: tanggalAsal.isEmpty ? null : tanggalAsal,
        idRitase: idRitase,
        items: items,
        fotoPenjemputanUrl: fotoUrl,
        catatan: _catatanCtrls[key]?.text.trim() ?? '',
      );
      if (!mounted) return;
      if (result != null) {
        var sAwb = 0, sKoli = 0, sEcer = 0, sHv = 0;
        final resItems = result['items'];
        if (resItems is List) {
          for (final it in resItems) {
            if (it is Map) {
              final sisa = it['sisa'];
              if (sisa is Map) {
                sAwb += _toInt(sisa['sisa_awb']);
                sKoli += _toInt(sisa['sisa_koli']);
                sEcer += _toInt(sisa['sisa_ecer']);
                sHv += _toInt(sisa['sisa_hv']);
              } else {
                sAwb += _toInt(it['sisa_awb']);
              }
            }
          }
        }
        final n = resItems is List ? resItems.length : items.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              n > 1
                  ? 'Tersimpan! $n implant. Sisa \u2014 $sAwb AWB, $sKoli koli, $sEcer ecer, $sHv HV.'
                  : 'Tersimpan! Sisa \u2014 $sAwb AWB, $sKoli koli, $sEcer ecer, $sHv HV.',
            ),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
        _selectedRitase.remove(key);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal konfirmasi: $e')));
    } finally {
      if (mounted) setState(() => _confirming.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _isLoading || _error != null
        ? <Map<String, dynamic>>[]
        : _formGroups();
    final subtitle = widget.implantName.isNotEmpty
        ? widget.implantName
        : (_implants.length > 1 ? '${_implants.length} implant' : '');

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
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.white70,
                ),
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
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0D47A1)),
            )
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              ),
            )
          : IndexedStack(
              index: _tabIndex,
              children: [_buildKonfirmasiTab(groups), _buildRiwayatTab()],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFDBEAFE),
        onDestinationSelected: (i) {
          setState(() => _tabIndex = i);
          if (i == 1) _loadHistory(showLoading: _history.isEmpty);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(
              Icons.fact_check_rounded,
              color: Color(0xFF0D47A1),
            ),
            label: 'Konfirmasi',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            selectedIcon: Icon(Icons.history_rounded, color: Color(0xFF0D47A1)),
            label: 'Riwayat',
          ),
        ],
      ),
    );
  }

  Widget _buildKonfirmasiTab(List<Map<String, dynamic>> groups) {
    return RefreshIndicator(
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
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 48,
                      color: Color(0xFF16A34A),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Tidak ada sisa maupun input baru',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...groups.map(_buildGroup),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildRiwayatTab() {
    final filterItems = const [
      ['today', 'Hari Ini'],
      ['week', '7 Hari'],
      ['month', 'Bulan Ini'],
      ['all', 'Semua'],
    ];
    return RefreshIndicator(
      onRefresh: () => _loadHistory(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filterItems.map((f) {
                final selected = _historyFilter == f[0];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f[1]),
                    selected: selected,
                    onSelected: (_) {
                      if (_historyFilter == f[0]) return;
                      setState(() => _historyFilter = f[0]);
                      _loadHistory();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          if (_implants.length > 1) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              key: ValueKey('history_implant_${_historyImplant ?? 0}'),
              initialValue: _historyImplant ?? 0,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Filter implant',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: [
                const DropdownMenuItem(value: 0, child: Text('Semua implant')),
                ..._implants.map((imp) {
                  final id = _toInt(imp['id_implant']);
                  return DropdownMenuItem(
                    value: id,
                    child: Text(
                      _str(imp['nama_implant']),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
              ],
              onChanged: (v) {
                setState(() => _historyImplant = (v ?? 0) > 0 ? v : null);
                _loadHistory();
              },
            ),
          ],
          const SizedBox(height: 12),
          if (_historyLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF0D47A1)),
              ),
            )
          else if (_historyError != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Column(
                children: [
                  Text(
                    _historyError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFB91C1C)),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _loadHistory(),
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            )
          else if (_history.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 44,
                    color: Color(0xFF94A3B8),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Belum ada riwayat konfirmasi',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            )
          else
            ..._history.map(_buildHistoryCard),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildGroup(Map<String, dynamic> g) {
    final key = g['key'] as String;
    final implants = _groupImplants(g);
    if (implants.length <= 1) {
      return _buildSingleCard(g, implants.isEmpty ? null : implants.first);
    }
    final busy = _confirming.contains(key);
    return Column(
      key: _groupKeys.putIfAbsent(key, () => GlobalKey()),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupHeader(g, implants, busy),
        const SizedBox(height: 10),
        ...implants.map((imp) => _buildImplantCard(g, imp, busy)),
        _buildGroupFooter(g, busy, implants.length),
      ],
    );
  }

  Widget _cardBox({
    required Widget child,
    Color border = const Color(0xFFBFDBFE),
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D47A1).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildGroupHeader(
    Map<String, dynamic> g,
    List<Map<String, dynamic>> implants,
    bool busy,
  ) {
    final key = g['key'] as String;
    final jenis = g['jenis'] as String;
    final ritKe = g['ritKe'] as int;
    final checked = _checkedIds(key);
    final sumber = checked.isEmpty
        ? implants
        : implants
              .where((imp) => checked.contains(_toInt(imp['id_implant'])))
              .toList();
    var awb = 0, koli = 0, ecer = 0, hv = 0;
    for (final imp in sumber) {
      final id = _toInt(imp['id_implant']);
      awb += _groupTotal(id, g, 'awb');
      koli += _groupTotal(id, g, 'koli');
      ecer += _groupTotal(id, g, 'ecer');
      hv += _groupTotal(id, g, 'hv');
    }
    var totalPending = 0;
    for (final imp in implants) {
      final p = _pendingEntry(_toInt(imp['id_implant']), jenis, ritKe);
      totalPending += _toInt(p?['jumlah_input']);
    }
    final pointNames = implants
        .map(_pointNameOf)
        .where((name) => name.isNotEmpty)
        .toSet();
    final pointLabel = pointNames.isEmpty
        ? 'Titik penjemputan'
        : pointNames.length == 1
        ? 'Titik: ${pointNames.first}'
        : '${pointNames.length} titik penjemputan';

    return _cardBox(
      border: const Color(0xFFBFDBFE),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D47A1), Color(0xFF2563EB)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Rit $ritKe',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  checked.isEmpty
                      ? 'Pilih implant yang ikut dijemput'
                      : '${checked.length} dari ${implants.length} implant dipilih'
                            '${totalPending > 0 ? ' \u2022 $totalPending input baru' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                size: 14,
                color: Color(0xFF2563EB),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  pointLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E40AF),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _statChip(
                'Sisa: $awb AWB',
                const Color(0xFFEDE9FE),
                const Color(0xFF6D28D9),
              ),
              _statChip(
                '$koli Koli',
                const Color(0xFFDBEAFE),
                const Color(0xFF1E40AF),
              ),
              _statChip(
                '$ecer Ecer',
                const Color(0xFFFEF9C3),
                const Color(0xFF854D0E),
              ),
              _statChip(
                '$hv HV',
                const Color(0xFFFEF3C7),
                const Color(0xFFB45309),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildDriverDropdown(g, busy),
        ],
      ),
    );
  }

  Widget _buildSingleCard(Map<String, dynamic> g, Map<String, dynamic>? imp) {
    final key = g['key'] as String;
    final jenis = g['jenis'] as String;
    final ritKe = g['ritKe'] as int;
    final busy = _confirming.contains(key);
    final id = imp == null ? 0 : _toInt(imp['id_implant']);
    final pending = _pendingEntry(id, jenis, ritKe);
    final sisa = _sisaEntry(id, jenis, ritKe);
    final count = _toInt(pending?['jumlah_input']);

    return Container(
      key: _groupKeys.putIfAbsent(key, () => GlobalKey()),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D47A1).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D47A1), Color(0xFF2563EB)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Rit $ritKe',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pending != null
                      ? '$count input belum terkonfirmasi'
                      : 'Sisa dari pengambilan sebelumnya',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                size: 14,
                color: Color(0xFF2563EB),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Titik: ${imp == null ? '-' : _pointNameOf(imp)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E40AF),
                  ),
                ),
              ),
            ],
          ),
          if (imp != null && _implants.length > 1) ...[
            const SizedBox(height: 6),
            Text(
              _str(imp['nama_implant']),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _statChip(
                'Sisa: ${_toInt(sisa?['sisa_awb'])} AWB',
                const Color(0xFFEDE9FE),
                const Color(0xFF6D28D9),
              ),
              _statChip(
                '${_toInt(sisa?['sisa_koli'])} Koli',
                const Color(0xFFDBEAFE),
                const Color(0xFF1E40AF),
              ),
              _statChip(
                '${_toInt(sisa?['sisa_ecer'])} Ecer',
                const Color(0xFFFEF9C3),
                const Color(0xFF854D0E),
              ),
              _statChip(
                '${_toInt(sisa?['sisa_hv'])} HV',
                const Color(0xFFFEF3C7),
                const Color(0xFFB45309),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDriverDropdown(g, busy),
          const SizedBox(height: 12),
          if (imp != null) ...[
            Container(
              key: _implantKeys.putIfAbsent(
                _ctrlKey(id, key),
                () => GlobalKey(),
              ),
            ),
            ..._buildTakenForm(id, key, jenis, ritKe, busy),
          ],
          _buildPhotoNote(key, busy),
          const SizedBox(height: 10),
          _buildConfirmButton(g, busy, 1),
        ],
      ),
    );
  }

  Widget _buildImplantCard(
    Map<String, dynamic> g,
    Map<String, dynamic> imp,
    bool busy,
  ) {
    final key = g['key'] as String;
    final jenis = g['jenis'] as String;
    final ritKe = g['ritKe'] as int;
    final id = _toInt(imp['id_implant']);
    final checked = _checkedIds(key).contains(id);
    final pending = _pendingEntry(id, jenis, ritKe);
    final awb = _groupTotal(id, g, 'awb');
    final koli = _groupTotal(id, g, 'koli');
    final ecer = _groupTotal(id, g, 'ecer');
    final hv = _groupTotal(id, g, 'hv');

    return Container(
      key: _implantKeys.putIfAbsent(_ctrlKey(id, key), () => GlobalKey()),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: checked ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
          width: checked ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: checked,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: busy
                    ? null
                    : (v) => _toggleImplant(g, id, v ?? false),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _str(imp['nama_implant']),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Titik: ${_pointNameOf(imp)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              if (pending != null)
                Text(
                  '${_toInt(pending['jumlah_input'])} input',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _statChip(
                'Sisa: $awb AWB',
                const Color(0xFFEDE9FE),
                const Color(0xFF6D28D9),
              ),
              _statChip(
                '$koli Koli',
                const Color(0xFFDBEAFE),
                const Color(0xFF1E40AF),
              ),
              _statChip(
                '$ecer Ecer',
                const Color(0xFFFEF9C3),
                const Color(0xFF854D0E),
              ),
              _statChip(
                '$hv HV',
                const Color(0xFFFEF3C7),
                const Color(0xFFB45309),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!checked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text(
                'Centang untuk ikut dijemput driver.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            )
          else
            ..._buildTakenForm(id, key, jenis, ritKe, busy),
        ],
      ),
    );
  }

  List<Widget> _buildTakenForm(
    int implantId,
    String key,
    String jenis,
    int ritKe,
    bool busy,
  ) {
    final ck = _ctrlKey(implantId, key);
    final visibleSections = _takenSections.where((section) {
      final fields = (section['fields'] as List).cast<Map<String, String>>();
      return fields.any(
        (f) => _sisaMetric(implantId, jenis, ritKe, f['key']!) > 0,
      );
    }).toList();
    if (visibleSections.isEmpty) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: const Text(
            'Tidak ada sisa barang \u2014 semua sudah diambil driver.',
            style: TextStyle(fontSize: 12, color: Color(0xFF15803D)),
          ),
        ),
        const SizedBox(height: 8),
      ];
    }
    return [
      const Text(
        'Jumlah yang diambil driver:',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF334155),
        ),
      ),
      const SizedBox(height: 2),
      const Text(
        'Hanya kolom yang bersisa yang tampil.',
        style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
      ),
      const SizedBox(height: 6),
      ...visibleSections.map(
        (section) => _buildTakenSection(
          ck,
          (section['title'] as String?) ?? '',
          ((section['fields'] as List?) ?? []).cast<Map<String, String>>(),
          busy,
          Color((section['color'] as int?) ?? 0xFF0D47A1),
        ),
      ),
    ];
  }

  Widget _buildDriverDropdown(Map<String, dynamic> g, bool busy) {
    final key = g['key'] as String;
    final loading = _loadingCandidates[key] ?? false;
    final candidates = _candidates[key] ?? [];
    final selected = _selectedRitase[key];

    if (loading) {
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            'Memuat driver...',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      );
    }
    if (candidates.isEmpty) {
      final pesan = _checkedIds(key).isEmpty
          ? 'Centang implant yang dijemput untuk melihat driver.'
          : 'Driver belum ditugaskan untuk mengambil muatan.';
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF9C3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFDE047)),
        ),
        child: Text(
          pesan,
          style: const TextStyle(fontSize: 12, color: Color(0xFF854D0E)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Driver yang datang mengambil:',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          key: ValueKey('${key}__${selected ?? 0}'),
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          hint: const Text('Pilih driver...', style: TextStyle(fontSize: 13)),
          items: candidates.map((r) {
            final id = _toInt(r['id_ritase']);
            final driver = _str(r['nama_driver']).isEmpty
                ? 'Driver'
                : _str(r['nama_driver']);
            final rKe = _toInt(r['ritase_ke']);
            final kode = _str(r['kode_ritase']);
            final jamMulai = _shortTime(_str(r['jam_mulai']));
            final jamSelesai = _shortTime(_str(r['jam_selesai']));
            final plat = _str(r['plat_nomor']);
            final jam = (jamMulai.isNotEmpty && jamSelesai.isNotEmpty)
                ? ' \u2022 $jamMulai-$jamSelesai'
                : '';
            final nopol = plat.isNotEmpty && plat != '-' ? ' \u2022 $plat' : '';
            final tgl = _tanggalLabel(_str(r['tanggal']));
            return DropdownMenuItem<int>(
              value: id,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    rKe > 0 ? '$driver \u2022 Rit $rKe' : driver,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (kode.isNotEmpty ||
                      jam.isNotEmpty ||
                      nopol.isNotEmpty ||
                      tgl.isNotEmpty)
                    Text(
                      '$kode$jam$nopol$tgl',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
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
                  if (v != null) {
                    _selectedRitase[key] = v;
                  } else {
                    _selectedRitase.remove(key);
                  }
                }),
        ),
      ],
    );
  }

  Widget _buildGroupFooter(Map<String, dynamic> g, bool busy, int total) {
    final key = g['key'] as String;
    final n = _checkedIds(key).length;
    return _cardBox(
      border: const Color(0xFFE2E8F0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            n == 0
                ? 'Belum ada implant yang dipilih'
                : 'Bukti serah terima \u2022 $n dari $total implant',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          _buildPhotoNote(key, busy),
          const SizedBox(height: 10),
          _buildConfirmButton(g, busy, n),
        ],
      ),
    );
  }

  Widget _buildPhotoNote(String key, bool busy) {
    final fotoPath = _handoverFoto[key];
    final uploading = _uploadingFoto.contains(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (busy || uploading)
                    ? null
                    : () => _pickHandoverFoto(key),
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
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _catatanCtrls.putIfAbsent(
            key,
            () => TextEditingController(),
          ),
          enabled: !busy,
          maxLines: 2,
          minLines: 1,
          decoration: InputDecoration(
            hintText: 'Catatan sisa, mis: 40 koli tidak muat...',
            hintStyle: const TextStyle(fontSize: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildConfirmButton(Map<String, dynamic> g, bool busy, int n) {
    final key = g['key'] as String;
    final enabled = _canConfirm(key) && !busy;
    final labelColor = enabled ? Colors.white : const Color(0xFF94A3B8);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF16A34A),
          disabledBackgroundColor: const Color(0xFFE2E8F0),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: enabled ? () => _confirm(g) : null,
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(Icons.check_rounded, color: labelColor),
        label: Text(
          busy
              ? 'Menyimpan...'
              : (n > 1
                    ? 'Konfirmasi Driver ($n implant)'
                    : 'Konfirmasi Driver'),
          style: TextStyle(color: labelColor, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildTakenSection(
    String ctrlKey,
    String title,
    List<Map<String, String>> fields,
    bool busy,
    Color accent,
  ) {
    if (fields.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: fields.map((f) {
              final mkey = f['key']!;
              final label = f['label']!;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: f == fields.last ? 0 : 8),
                  child: TextField(
                    controller: _takenCtrls[ctrlKey]?[mkey],
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: label,
                      labelStyle: TextStyle(fontSize: 10, color: accent),
                      hintText: '0',
                      hintStyle: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                      ),
                      filled: true,
                      fillColor: accent.withValues(alpha: 0.06),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: accent.withValues(alpha: 0.35),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: accent, width: 1.5),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> item) {
    final status = _str(item['status']);
    final isLate = status == 'terlambat';
    final isMissed = status == 'terlewat' || isLate;
    final color = isMissed ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
    final bg = isMissed ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4);
    final label = isLate
        ? 'Terlambat diambil'
        : isMissed
        ? 'Terlambat'
        : 'Diambil';
    final asal = _toInt(item['ritase_ke']);
    final aktual = _toInt(item['ritase_ke_aktual']);
    final driver = _str(item['nama_driver']);
    final kode = _str(item['kode_ritase']);
    final implant = _str(item['nama_implant']);
    final tgl = _str(item['tanggal_aktual']).isNotEmpty
        ? _str(item['tanggal_aktual'])
        : _str(item['tanggal_input']);
    final waktu = _fmtTime(_str(item['created_at']));
    final awb = _toInt(item['jumlah_awb'] ?? item['total_awb']);
    final koli = _toInt(item['total_koli']);
    final ecer = _toInt(item['total_ecer']);
    final hv = _toInt(item['total_hv']);
    final foto = _str(item['foto_penjemputan_url']);
    final catatan = _str(item['catatan']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  driver.isEmpty ? 'Driver' : driver,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (waktu.isNotEmpty)
                Text(
                  waktu,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isLate
                ? 'Rit $asal \u2192 Rit $aktual'
                : isMissed
                ? 'Rit $asal${tgl.isNotEmpty ? ' \u2022 ${_tanggalLabel(tgl)}' : ''} \u2022 belum diambil'
                : 'Rit $asal',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (implant.isNotEmpty)
            Text(
              'Implant: $implant',
              style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
            ),
          if (kode.isNotEmpty || tgl.isNotEmpty)
            Text(
              '$kode${tgl.isNotEmpty ? ' \u2022 $tgl' : ''}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _statChip(
                '$awb AWB',
                const Color(0xFFEDE9FE),
                const Color(0xFF6D28D9),
              ),
              _statChip(
                '$koli koli',
                const Color(0xFFDBEAFE),
                const Color(0xFF1E40AF),
              ),
              _statChip(
                '$ecer ecer',
                const Color(0xFFFEF9C3),
                const Color(0xFF854D0E),
              ),
              _statChip(
                '$hv HV',
                const Color(0xFFFEF3C7),
                const Color(0xFFB45309),
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
                catatan,
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ],
          if (foto.isNotEmpty) ...[
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => _showFotoDialog(foto),
              icon: const Icon(Icons.photo_rounded, size: 16),
              label: const Text(
                'Lihat Foto Bukti',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
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

  Widget _statChip(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
