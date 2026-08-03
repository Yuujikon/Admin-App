import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _local  = FlutterLocalNotificationsPlugin();
  static final _fcm    = FirebaseMessaging.instance;

  static const _ordersChannel = AndroidNotificationChannel(
    'gdc_orders', 'Order Updates',
    description: 'Order status and pickup reminders',
    importance: Importance.high,
  );

  static const _alertsChannel = AndroidNotificationChannel(
    'gdc_alerts', 'Store Alerts',
    description: 'Low stock and perishable warnings',
    importance: Importance.defaultImportance,
  );

  static Future<void> initialize() async {
    // Request permission (Android 13+, iOS)
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // Set up local notifications (for foreground FCM messages)
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(const InitializationSettings(android: androidSettings));

    final androidImpl = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(_ordersChannel);
    await androidImpl?.createNotificationChannel(_alertsChannel);

    // Show notification when app is in foreground
    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n == null) return;
      _local.show(
        n.hashCode,
        n.title,
        n.body,
        const NotificationDetails(android: AndroidNotificationDetails(
          'gdc_orders', 'Order Updates',
          importance: Importance.high, priority: Priority.high,
        )),
      );
    });

    // Get and print FCM token (send this to your server/Cloud Function)
    final token = await _fcm.getToken();
    // await _fcm.getToken();
    // debugPrint('FCM Token: $token');
  }

  // Local notification — order ready
  static Future<void> sendOrderReady(String orderId) =>
      _local.show(
        orderId.hashCode,
        'Order Ready! 🛍️',
        'Order $orderId is packed and ready for pickup.',
        const NotificationDetails(android: AndroidNotificationDetails(
          'gdc_orders', 'Order Updates',
          importance: Importance.high, priority: Priority.high,
        )),
      );

  static Future<void> showRefundRequestAlert(String transactionId, String customer) =>
      _local.show(
        transactionId.hashCode + 2,
        'New Refund Request 💸',
        'Customer $customer is requesting a refund for sale #$transactionId.',
        const NotificationDetails(android: AndroidNotificationDetails(
          'gdc_orders', 'Order Updates',
          importance: Importance.high, priority: Priority.high,
        )),
      );

  static Future<void> showLowStockSupplierAlert(String productName, String supplierName, String phone) =>
      _local.show(
        productName.hashCode + 3,
        'Low Stock: Call Supplier 📞',
        '$productName is low! Contact $supplierName at $phone.',
        const NotificationDetails(android: AndroidNotificationDetails(
          'gdc_alerts', 'Store Alerts',
          importance: Importance.high, priority: Priority.high,
        )),
      );

  static Future<void> sendRefundUpdate(String transactionId, bool approved) =>
      _local.show(
        transactionId.hashCode,
        approved ? 'Refund Approved ✅' : 'Refund Rejected ❌',
        'Your request for sale #${transactionId.length > 8 ? transactionId.substring(0, 8) : transactionId} has been ${approved ? 'approved' : 'rejected'}.',
        const NotificationDetails(android: AndroidNotificationDetails(
          'gdc_orders', 'Order Updates',
          importance: Importance.high, priority: Priority.high,
        )),
      );

  static Future<void> sendOrderAutoCancelled(String orderId) =>
      _local.show(
        orderId.hashCode + 1,
        'Order Expired ⚠️',
        'Order $orderId was cancelled as the pickup window has passed. Items restocked.',
        const NotificationDetails(android: AndroidNotificationDetails(
          'gdc_orders', 'Order Updates',
          importance: Importance.high, priority: Priority.high,
        )),
      );

  // Schedule a local reminder for perishable orders
  static Future<void> schedulePerishableReminder(String id, String orderId) async {
    // Show a reminder notification now (true scheduling needs flutter_local_notifications zonedSchedule)
    await _local.show(
      '${id}remind'.hashCode,
      'Perishable Order Placed ⏰',
      'Order $orderId must be collected within 2 hours or it will be auto-cancelled.',
      const NotificationDetails(android: AndroidNotificationDetails(
        'gdc_alerts', 'Store Alerts',
        importance: Importance.defaultImportance,
      )),
    );
  }
}