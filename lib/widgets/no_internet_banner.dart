import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Banner status koneksi internet global yang adaptif & halus (modern mobile UX).
class NoInternetBanner extends StatefulWidget {
  final Widget child;

  const NoInternetBanner({super.key, required this.child});

  @override
  State<NoInternetBanner> createState() => _NoInternetBannerState();
}

class _NoInternetBannerState extends State<NoInternetBanner>
    with SingleTickerProviderStateMixin {
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _isOffline = false;
  bool _showReconnected = false;
  Timer? _reconnectedTimer;

  @override
  void initState() {
    super.initState();
    _checkInitialConnectivity();
    _subscription = Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
  }

  Future<void> _checkInitialConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      _updateConnectionStatus(results);
    } catch (_) {}
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final offline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);

    if (_isOffline && !offline) {
      // Baru saja kembali online -> Tampilkan banner hijau sebentar lalu hilangkan
      setState(() {
        _isOffline = false;
        _showReconnected = true;
      });
      _reconnectedTimer?.cancel();
      _reconnectedTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showReconnected = false;
          });
        }
      });
    } else if (offline != _isOffline) {
      setState(() {
        _isOffline = offline;
        if (offline) _showReconnected = false;
      });
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    _reconnectedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 300),
          crossFadeState: (_isOffline || _showReconnected)
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Material(
            elevation: 3,
            child: Container(
              width: double.infinity,
              color: _isOffline ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
              child: SafeArea(
                bottom: false,
                top: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isOffline
                            ? Icons.wifi_off_rounded
                            : Icons.wifi_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isOffline
                            ? 'Tidak ada koneksi internet'
                            : 'Koneksi internet terhubung kembali',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
