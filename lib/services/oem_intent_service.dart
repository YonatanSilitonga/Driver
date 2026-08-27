import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service otomatis untuk deteksi merk HP & launching Intent Auto-Start / Background Manager spesifik OEM.
class OemIntentService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Ambil nama manufaktur/merk HP (lowercase)
  static Future<String> getManufacturer() async {
    if (!Platform.isAndroid) return 'other';
    try {
      final androidInfo = await _deviceInfo.androidInfo;
      return androidInfo.manufacturer.toLowerCase();
    } catch (_) {
      return 'other';
    }
  }

  /// Ambil label merk HP yang rapi untuk UI
  static Future<String> getBrandName() async {
    final mfr = await getManufacturer();
    if (mfr.contains('transsion') || mfr.contains('infinix') || mfr.contains('tecno') || mfr.contains('itel')) {
      return 'Infinix / Tecno (XOS)';
    }
    if (mfr.contains('oppo') || mfr.contains('realme') || mfr.contains('oneplus')) {
      return 'OPPO / Realme (ColorOS)';
    }
    if (mfr.contains('xiaomi') || mfr.contains('redmi') || mfr.contains('poco')) {
      return 'Xiaomi / Redmi (MIUI / HyperOS)';
    }
    if (mfr.contains('vivo') || mfr.contains('iqoo')) {
      return 'Vivo / iQOO (Funtouch OS)';
    }
    if (mfr.contains('samsung')) {
      return 'Samsung (One UI)';
    }
    if (mfr.contains('huawei') || mfr.contains('honor')) {
      return 'Huawei / Honor (EMUI)';
    }
    if (mfr.contains('asus')) {
      return 'ASUS (ZenUI)';
    }
    return 'Android Standard ($mfr)';
  }

  /// Buka halaman Pengaturan Auto-Start / Background Activity spesifik merk HP
  static Future<bool> launchOemAutoStartSettings() async {
    if (!Platform.isAndroid) return false;
    final mfr = await getManufacturer();

    final intents = <Map<String, String>>[];

    if (mfr.contains('transsion') || mfr.contains('infinix') || mfr.contains('tecno') || mfr.contains('itel')) {
      intents.addAll([
        {
          'package': 'com.transsion.phonemanager',
          'component': 'com.transsion.phonemanager.autostart.AutoStartManagementActivity',
        },
        {
          'package': 'com.transsion.phonemanager',
          'component': 'com.transsion.phonemanager.main.MainActivity',
        },
      ]);
    } else if (mfr.contains('oppo') || mfr.contains('realme') || mfr.contains('oneplus')) {
      intents.addAll([
        {
          'package': 'com.coloros.safecenter',
          'component': 'com.coloros.safecenter.startupapp.StartupAppListActivity',
        },
        {
          'package': 'com.oppo.safe',
          'component': 'com.oppo.safe.permission.startup.StartupAppListActivity',
        },
        {
          'package': 'com.coloros.safecenter',
          'component': 'com.coloros.safecenter.permission.startup.StartupAppListActivity',
        },
      ]);
    } else if (mfr.contains('xiaomi') || mfr.contains('redmi') || mfr.contains('poco')) {
      intents.addAll([
        {
          'package': 'com.miui.securitycenter',
          'component': 'com.miui.permcenter.autostart.AutoStartManagementActivity',
        },
      ]);
    } else if (mfr.contains('vivo') || mfr.contains('iqoo')) {
      intents.addAll([
        {
          'package': 'com.iqoo.secure',
          'component': 'com.iqoo.secure.ui.phoneoptimize.BgStartUpManager',
        },
        {
          'package': 'com.vivo.permissionmanager',
          'component': 'com.vivo.permissionmanager.activity.BgStartUpManagerActivity',
        },
      ]);
    } else if (mfr.contains('huawei') || mfr.contains('honor')) {
      intents.addAll([
        {
          'package': 'com.huawei.systemmanager',
          'component': 'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity',
        },
        {
          'package': 'com.huawei.systemmanager',
          'component': 'com.huawei.systemmanager.optimize.process.ProtectActivity',
        },
      ]);
    } else if (mfr.contains('asus')) {
      intents.addAll([
        {
          'package': 'com.asus.mobilemanager',
          'component': 'com.asus.mobilemanager.autostart.AutoStartActivity',
        },
      ]);
    }

    for (final item in intents) {
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: item['package'],
          componentName: item['component'],
        );
        await intent.launch();
        return true;
      } catch (e) {
        debugPrint('[OEM INTENT] Gagal launch ${item['package']}: $e');
      }
    }

    // Fallback: buka App Settings standar jika intent spesifik tidak ditemukan/error
    try {
      return await openAppSettings();
    } catch (_) {
      return false;
    }
  }
}
