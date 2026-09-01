import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/background_tracking.dart';
import '../services/app_updater.dart';
import '../utils/network_exception.dart';
import 'home_screen.dart';
import 'forgot_password_screen.dart';
import 'permission_guide_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // --- 1. Deklarasi Controller & State Variables ---
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordObscured = true;

  // --- 2. Deklarasi Warna Brand ---
  final Color primaryBlue = const Color(0xFF115C93);
  final Color primaryOrange = const Color(0xFFF27D26);

  // --- 3. Helper Method _toInt ---
  int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? fallback;
  }

  void _showErrorSnack(dynamic error) {
    if (!mounted) return;
    final netEx = NetworkException.from(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              netEx.isNoInternet
                  ? Icons.wifi_off_rounded
                  : (netEx.isTimeout
                      ? Icons.timer_off_outlined
                      : Icons.error_outline_rounded),
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                netEx.message,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppUpdater.checkUpdate(context);
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final usernameOrEmail = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    // Validasi wajib — tanpa input tidak boleh masuk (no trial mode).
    if (usernameOrEmail.isEmpty || password.isEmpty) {
      _showErrorSnack(
        const NetworkException(
          message: 'Username dan password wajib diisi.',
          type: NetworkErrorType.badRequest,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = await AuthService.login(usernameOrEmail, password);
      if (mounted) {
        if (user != null) {
          // Set identitas tracking dari akun yang login
          try {
            final cfg = await ApiClient.loadDriverConfig();
            final idDriver = _toInt(
              user['id_driver'],
              fallback: cfg['id_driver'] ?? 0,
            );
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
            } catch (_) {
              /* fallback ke config */
            }
            final driverName =
                (user['nama'] ?? user['name'] ?? user['username'] ?? 'Driver')
                    .toString();
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

          final nameToShow =
              user['username'] ?? user['nama'] ?? user['name'] ?? 'Driver';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
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

          // Guide izin muncul sekali (pertama install/login) — bisa dilewati.
          await PermissionGuideScreen.maybeShowOnce(context);

          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 400),
              pageBuilder: (_, _, _) => const HomeScreen(),
              transitionsBuilder: (_, animation, _, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
            (route) => false,
          );
        } else {
          setState(() => _isLoading = false);
          _showErrorSnack(
            const NetworkException(
              message: 'Login gagal. Periksa kembali username/password.',
              type: NetworkErrorType.unauthorized,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnack(e);
      }
    }
  }

  Future<bool> _showExitConfirmationDialog() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.exit_to_app_rounded, color: Color(0xFF0D47A1)),
            SizedBox(width: 10),
            Text(
              'Keluar Aplikasi',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Apakah Anda yakin ingin keluar dari aplikasi MustGo?',
          style: TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Batal',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Keluar',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _showExitConfirmationDialog();
        if (shouldExit) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: const Color(0xFFF8F9FA),
        body: Stack(
          children: [
            // 1. BACKGROUND MAP PATTERN / GRADIENT
            Positioned.fill(
              child: Opacity(
                opacity: 0.55,
                child: Image.asset(
                  'assets/images/map_bg.png',
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                  errorBuilder: (context, error, stackTrace) =>
                      Container(color: const Color(0xFFF8F9FA)),
                ),
              ),
            ),

            // 2. KONTEN UTAMA (SCROLLABLE)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 60),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Image.asset(
                        'assets/images/logo_mustgo.png',
                        height: 120,
                        width: 120,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.local_shipping_rounded,
                              size: 80,
                              color: Color(0xFF0D47A1),
                            ),
                      ),

                      const SizedBox(height: 32),

                      // KARTU FORM LOGIN
                      Container(
                        padding: const EdgeInsets.all(28.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Judul & Subtitle
                            const Text(
                              "Selamat Datang",
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Silahkan login menggunakan akun anda masing masing",
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF64748B),
                              ),
                            ),

                            const SizedBox(height: 32),

                            // Input Username
                            TextField(
                              controller: _usernameController,
                              decoration: InputDecoration(
                                labelText: 'Username',
                                labelStyle: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                ),
                                enabledBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFCBD5E1),
                                  ),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: primaryBlue,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Input Password
                            TextField(
                              controller: _passwordController,
                              obscureText: _isPasswordObscured,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                labelStyle: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                ),
                                enabledBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFFCBD5E1),
                                  ),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: primaryBlue,
                                    width: 2,
                                  ),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isPasswordObscured
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: const Color(0xFF94A3B8),
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isPasswordObscured =
                                          !_isPasswordObscured;
                                    });
                                  },
                                ),
                              ),
                            ),

                            const SizedBox(height: 36),

                            // Tombol Log In
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryOrange,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  "Log In",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),

                            // Lupa password (tanpa OTP â€” verifikasi username + no_hp)
                            Align(
                              alignment: Alignment.center,
                              child: TextButton(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const ForgotPasswordScreen(),
                                  ),
                                ),
                                child: const Text(
                                  'Lupa password?',
                                  style: TextStyle(
                                    color: Color(0xFF115C93),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: FutureBuilder<PackageInfo>(
                          future: PackageInfo.fromPlatform(),
                          builder: (context, snapshot) {
                            final v = snapshot.data?.version ?? '1.0.3';
                            return Text(
                              'Versi $v',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF115C93),
                                letterSpacing: 0.5,
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ),

            // 3. AKSEN GELOMBANG BAWAH (ORANGE & BLUE WAVE)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Image.asset(
                  'assets/images/bottom_waves.png',
                  width: MediaQuery.of(context).size.width,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),

            // 4. SIMPLE CLEAN LOADING OVERLAY
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
