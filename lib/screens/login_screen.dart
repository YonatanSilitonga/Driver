import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/background_tracking.dart';
import 'main_layout.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Warna sesuai mockup
  static const Color _navy = Color(0xFF1E293B);
  static const Color _blueBtn = Color(0xFF2F5CDB);
  static const Color _orange = Color(0xFFF5A623);
  static const Color _blueWave = Color(0xFF2B4FD1);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final usernameOrEmail = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (usernameOrEmail.isNotEmpty && password.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        final user = await AuthService.login(usernameOrEmail, password);
        if (mounted) {
          if (user != null) {
            // Set identitas tracking dari akun yang login
            try {
              final cfg = await ApiClient.loadDriverConfig();
              final idDriver = _toInt(user['id_driver'], fallback: cfg['id_driver'] ?? 0);
              var idKendaraan = cfg['id_kendaraan'] ?? 2;
              try {
                final res = await ApiClient.dio.get('/armada/ritase');
                final body = res.data;
                final data = (body is Map && body['data'] is List)
                    ? body['data'] as List
                    : const <dynamic>[];
                if (data.isNotEmpty && data.first is Map) {
                  final first = data.first as Map;
                  final kid = _toInt(first['id_kendaraan']);
                  if (kid > 0) idKendaraan = kid;
                }
              } catch (_) {/* fallback ke config */}
              final driverName = (user['nama'] ?? user['name'] ?? user['username'] ?? 'AWALUDIN').toString();
              await ApiClient.saveDriverConfig(
                idDriver: idDriver,
                idKendaraan: idKendaraan,
                idRitase: 0,
                driverName: driverName,
              );
            } catch (e) {
              // ignore: avoid_print
              print('⚠️ Gagal set config tracking: $e');
            }

            // Background tracking
            try {
              await startBackgroundTracking();
            } catch (_) {}

            if (!mounted) return;
            setState(() => _isLoading = false);

            final nameToShow = user['username'] ?? user['nama'] ?? user['name'] ?? 'Driver';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Selamat datang, $nameToShow',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFF0D47A1),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                margin: const EdgeInsets.all(16),
                duration: const Duration(seconds: 2),
              ),
            );

            Navigator.of(context).pushAndRemoveUntil(
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 400),
                pageBuilder: (_, __, ___) => const MainLayout(),
                transitionsBuilder: (_, animation, __, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
              ),
              (route) => false,
            );
          } else {
            setState(() => _isLoading = false);
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
          );
        }
      }
    } else {
      // Masuk mode trial jika kosong
      setState(() => _isLoading = true);
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => const MainLayout(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.expand(
        child: Stack(
        children: [
          // ==== Background gradient krem -> lavender ====
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFBE7CE), Color(0xFFF3E4E4), Color(0xFFE7E2F5)],
                  stops: [0.0, 0.45, 1.0],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),

          // ==== Wave oranye pojok kiri atas ====
          Positioned(
            top: 0,
            left: 0,
            child: ClipPath(
              clipper: _TopCornerClipper(),
              child: Container(
                width: size.width * 0.6,
                height: size.height * 0.09,
                color: _orange,
              ),
            ),
          ),

          // ==== Wave dekoratif bawah (oranye + biru) ====
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: size.height * 0.16,
              child: Stack(
                children: [
                  ClipPath(
                    clipper: _BottomWaveClipper(offset: 0.0),
                    child: Container(color: _orange),
                  ),
                  ClipPath(
                    clipper: _BottomWaveClipper(offset: 18.0),
                    child: Container(color: _blueWave),
                  ),
                ],
              ),
            ),
          ),

          // ==== Konten utama ====
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 36),

                  // ==== Slot Logo (gambar dipasang manual oleh user) ====
                  Container(
                    width: 130,
                    height: 130,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        // Placeholder sementara selama asset logo belum dipasang
                        return const Center(
                          child: Icon(
                            Icons.local_shipping_rounded,
                            size: 48,
                            color: _navy,
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ==== Kartu Login ====
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Login',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Satu Aplikasi untuk Semua Perjalanan',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),

                        const SizedBox(height: 28),

                        // Email
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: 'you@example.com',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: _blueBtn, width: 1.5),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Password
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: _blueBtn, width: 1.5),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                size: 20,
                                color: Colors.black38,
                              ),
                              onPressed: () =>
                                  setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                        ),

                        const SizedBox(height: 26),

                        // Tombol Log In
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _blueBtn,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'Log In',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: size.height * 0.1),
                ],
              ),
            ),
          ),

          // ==== Simple Clean Loading Overlay ====
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Color(0xFF0D47A1),
                            strokeWidth: 3,
                          ),
                        ),
                        SizedBox(width: 16),
                        Text(
                          'Memuat...',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }
}

/// Clipper untuk wave oranye kecil di pojok kiri atas.
class _TopCornerClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width * 0.75, 0);
    path.quadraticBezierTo(size.width * 0.2, size.height * 0.4, 0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Clipper untuk wave dekoratif di bagian bawah (dipakai dua kali dengan offset berbeda).
class _BottomWaveClipper extends CustomClipper<Path> {
  final double offset;
  _BottomWaveClipper({required this.offset});

  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.55 + offset);
    path.quadraticBezierTo(
      size.width * 0.3,
      size.height * 0.2 + offset,
      size.width * 0.55,
      size.height * 0.45 + offset,
    );
    path.quadraticBezierTo(
      size.width * 0.8,
      size.height * 0.7 + offset,
      size.width,
      size.height * 0.35 + offset,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => oldClipper != this;
}

/// Konversi aman ke int — tahan null, tipe salah, dan String.
int _toInt(dynamic v, {dynamic fallback = 0}) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? (fallback is num ? fallback.toInt() : 0);
  if (v == null && fallback is num) return fallback.toInt();
  return 0;
}