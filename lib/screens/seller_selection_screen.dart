import 'package:flutter/material.dart';
import '../services/api_client.dart';
import 'kapten_home_screen.dart';

class SellerSelectionScreen extends StatefulWidget {
  const SellerSelectionScreen({super.key});

  @override
  State<SellerSelectionScreen> createState() => _SellerSelectionScreenState();
}

class _SellerSelectionScreenState extends State<SellerSelectionScreen> {
  List<Map<String, dynamic>> _sellers = [];
  bool _isLoading = true;
  String? _error;
  bool _isSelecting = false;

  @override
  void initState() {
    super.initState();
    _loadSellers();
  }

  Future<void> _loadSellers() async {
    try {
      final sellers = await ApiClient.getMySellers();
      if (mounted) {
        setState(() {
          _sellers = sellers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Gagal memuat daftar seller: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectSeller(Map<String, dynamic> seller) async {
    final sellerId = seller['id_seller'] as int?;
    if (sellerId == null) return;

    setState(() => _isSelecting = true);

    try {
      final result = await ApiClient.selectSeller(sellerId);
      if (result != null && mounted) {
        final token = result['token'] as String?;
        if (token != null && token.isNotEmpty) {
          await ApiClient.saveToken(token);
          await ApiClient.saveSellerId(sellerId);
          await ApiClient.saveUserRole('kapten');

          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const KaptenHomeScreen()),
          ).then((_) {
            if (mounted) _loadSellers();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSelecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memilih seller: $e'),
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
                'Pilih seller implant yang sedang Anda kerjakan:',
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
                _loadSellers();
              },
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      );
    }

    if (_sellers.isEmpty) {
      return const Center(
        child: Text(
          'Tidak ada seller yang tersedia',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      );
    }

    return ListView.separated(
      itemCount: _sellers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final seller = _sellers[index];
        final namaSeller = seller['nama_seller'] ?? '-';
        final kodeSeller = seller['kode_seller'] ?? '';

        return InkWell(
          onTap: _isSelecting ? null : () => _selectSeller(seller),
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
                        namaSeller,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (kodeSeller.isNotEmpty)
                        Text(
                          kodeSeller,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
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
