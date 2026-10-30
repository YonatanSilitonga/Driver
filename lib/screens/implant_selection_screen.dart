import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'kapten_home_screen.dart';
import 'login_screen.dart';

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

  /// Implant yang terakhir dipakai (dari sesi sebelumnya) — ditandai agar
  /// kapten cukup satu tap untuk lanjut, tanpa logout.
  int _savedImplantId = 0;

  @override
  void initState() {
    super.initState();
    _loadImplants();
  }

  Future<void> _loadImplants() async {
    try {
      final saved = await ApiClient.getImplantId();
      final implants = await ApiClient.getMyImplants();
      if (mounted) {
        setState(() {
          _savedImplantId = saved;
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
          setState(() => _savedImplantId = implantId);
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const KaptenHomeScreen()),
          );
          if (mounted) {
            setState(() => _isSelecting = false);
            _loadImplants();
          }
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

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Yakin ingin keluar dari aplikasi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Pilih Implant',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
            onPressed: _isSelecting ? null : _handleLogout,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.store, size: 44, color: Color(0xFFFEA103)),
              const SizedBox(height: 12),
              const Text(
                'Pilih implant yang sedang Anda kerjakan:',
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              Expanded(child: _buildContent()),
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
        final titikImplant = (implant['nama_titik_implant'] ?? '').toString();
        final isLastUsed =
            _savedImplantId > 0 &&
            (implant['id_implant'] as int?) == _savedImplantId;

        return InkWell(
          onTap: _isSelecting ? null : () => _selectImplant(implant),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isLastUsed
                    ? const Color(0xFFFEA103)
                    : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
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
                    color: const Color(0xFFFEA103).withValues(alpha: 0.1),
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
                      Row(
                        children: [
                          if (titikImplant.isNotEmpty &&
                              titikImplant != namaImplant)
                            Text(
                              'Titik: $titikImplant',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                          if (isLastUsed) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Terakhir dipakai',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFB45309),
                                ),
                              ),
                            ),
                          ],
                        ],
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
                  const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        );
      },
    );
  }
}
