import 'package:flutter/material.dart';
import '../services/api_client.dart';
import 'kapten_home_screen.dart';

class ImplantSelectionScreen extends StatefulWidget {
  const ImplantSelectionScreen({super.key});

  @override
  State<ImplantSelectionScreen> createState() => _ImplantSelectionScreenState();
}

class _ImplantSelectionScreenState extends State<ImplantSelectionScreen> {
  List<Map<String, dynamic>> _implants = [];
  bool _isLoading = true;
  String? _error;
  bool _isSelecting = false;

  @override
  void initState() {
    super.initState();
    _loadImplants();
  }

  Future<void> _loadImplants() async {
    try {
      final implants = await ApiClient.getMyImplants();
      if (mounted) {
        setState(() {
          _implants = implants;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Gagal memuat daftar implant: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectImplant(Map<String, dynamic> implant) async {
    final implantId = implant['id_implant'] as int?;
    if (implantId == null) return;

    setState(() => _isSelecting = true);

    try {
      final result = await ApiClient.selectImplant(implantId);
      if (result != null && mounted) {
        final token = result['token'] as String?;
        if (token != null && token.isNotEmpty) {
          await ApiClient.saveToken(token);
          await ApiClient.saveImplantId(implantId);
          await ApiClient.saveUserRole('kapten');

          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const KaptenHomeScreen()),
          ).then((_) {
            if (mounted) _loadImplants();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSelecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memilih implant: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const Icon(
                Icons.store,
                size: 48,
                color: Color(0xFFFEA103),
              ),
              const SizedBox(height: 16),
              const Text(
                'Pilih Implant',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pilih implant yang sedang Anda kerjakan:',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFEA103)),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _loadImplants();
                },
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      );
    }

    if (_implants.isEmpty) {
      return const Center(
        child: Text(
          'Tidak ada implant yang tersedia',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      );
    }

    return ListView.separated(
      itemCount: _implants.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final implant = _implants[index];
        final namaImplant = implant['nama_implant'] ?? '-';
        final kodeImplant = implant['kode_implant'] ?? '';
        final peran = implant['peran'] ?? 'utama';

        return InkWell(
          onTap: _isSelecting ? null : () => _selectImplant(implant),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEA103).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.store,
                    color: Color(0xFFFEA103),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        namaImplant,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (kodeImplant.isNotEmpty)
                        Text(
                          kodeImplant,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      Text(
                        peran == 'cadangan' ? 'Cadangan' : 'Utama',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: peran == 'cadangan'
                              ? const Color(0xFF0284C7)
                              : const Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isSelecting)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFEA103),
                    ),
                  )
                else
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFF94A3B8),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
