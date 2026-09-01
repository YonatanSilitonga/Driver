import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/background_tracking.dart';
import '../utils/network_exception.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'permission_guide_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;

  double _progress = 0.0;
  String _loadingText = 'Menghubungkan ke Server...';
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _controller.forward();
    _startLoadingSequence();
  }

  void _startLoadingSequence() {
    _progressTimer = Timer.periodic(const Duration(milliseconds: 35), (timer) {
      if (!mounted) return;
      setState(() {
        _progress += 0.02;
        if (_progress >= 0.35 && _progress < 0.70) {
          _loadingText = 'Memeriksa Konfigurasi Fleet...';
        } else if (_progress >= 0.70 && _progress < 0.95) {
          _loadingText = 'Menyiapkan Dashboard...';
        } else if (_progress >= 1.0) {
          _progress = 1.0;
          _loadingText = 'Selesai!';
          _progressTimer?.cancel();
          _navigateToLogin();
        }
      });
    });
  }

  void _navigateToLogin() {
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _goAfterSplash();
    });
  }

  /// Setelah splash: kalau masih ada sesi valid → langsung dashboard (auto-login),
  /// selain itu → halaman login.
  Future<void> _goAfterSplash() async {
    if (!mounted) return;
    Widget destination = const LoginScreen();

    try {
      final hasToken = await ApiClient.isLoggedIn();
      if (hasToken) {
        try {
          final user = await AuthService.me();
          if (user != null) {
            destination = const HomeScreen();
            try {
              await startBackgroundTracking();
            } catch (_) {}
          } else {
            // Token invalid/expired dari server → bersihkan sesi
            await ApiClient.clearToken();
          }
        } on NetworkException catch (netErr) {
          if (netErr.type == NetworkErrorType.unauthorized) {
            // Sesi memang sudah invalid dari server (401/403)
            await ApiClient.clearToken();
          } else {
            // Offline atau timeout saat validasi -> Tetap masuk ke HomeScreen (Offline-First)
            destination = const HomeScreen();
            try {
              await startBackgroundTracking();
            } catch (_) {}
          }
        } catch (_) {
          // Error jaringan umum -> Masuk ke HomeScreen (Offline-First)
          destination = const HomeScreen();
        }
      }
    } catch (_) {
      destination = const LoginScreen();
    }

    if (!mounted) return;
    // Guide izin muncul sekali (auto-login juga) — bisa dilewati.
    await PermissionGuideScreen.maybeShowOnce(context);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F172A), // Deep Slate
              Color(0xFF1E293B),
              Color(0xFF0D47A1), // Navy Blue
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background Pulse Rings Glow
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: 260 * _pulseAnimation.value,
                  height: 260 * _pulseAnimation.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                  ),
                );
              },
            ),
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: 190 * _pulseAnimation.value,
                  height: 190 * _pulseAnimation.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF8F00).withValues(alpha: 0.15),
                  ),
                );
              },
            ),

            // Content Center
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),

                  // Logo Card Animation
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.4),
                              blurRadius: 30,
                              spreadRadius: 5,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(50),
                          child: Image.asset(
                            'assets/images/logo_mustgo.png',
                            width: 90,
                            height: 90,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.local_shipping_rounded,
                                size: 80,
                                color: Color(0xFF0D47A1),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // App Title & Tagline
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'MUST',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 2,
                              ),
                            ),
                            Text(
                              'GO',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFFFF8F00),
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8F00).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFFF8F00).withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Text(
                            'DRIVER LOGISTICS & FLEET SYSTEM',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFFC107),
                              letterSpacing: 1.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Animated Progress Indicator & Text
                  Column(
                    children: [
                      Text(
                        _loadingText,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: size.width * 0.65,
                          height: 6,
                          child: LinearProgressIndicator(
                            value: _progress,
                            backgroundColor: Colors.white.withValues(alpha: 0.15),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFFFF8F00),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
