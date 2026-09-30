import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter wrapper for Android Lock Task (Screen Pinning / Kiosk Mode).
class KioskLockdown {
  static const MethodChannel _channel = MethodChannel('com.gdc.sari_sari/kiosk');

  /// Starts Android Screen Pinning / Lock Task mode.
  /// Prevents cashiers from exiting the POS app, pressing Home/Recents, or switching windows.
  static Future<bool> startKioskMode() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>('startLockTask');
      debugPrint('KioskLockdown: Screen pinning started ✅');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('KioskLockdown Error: $e');
      return false;
    }
  }

  /// Stops Android Screen Pinning / Lock Task mode.
  static Future<bool> stopKioskMode() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>('stopLockTask');
      debugPrint('KioskLockdown: Screen pinning stopped.');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('KioskLockdown Error: $e');
      return false;
    }
  }
}
