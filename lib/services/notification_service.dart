import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _local  = FlutterLocalNotificationsPlugin();
  static final _fcm    = FirebaseMessaging.instance;

  static const _adminChannel = AndroidNotificationChannel(
    'gdc_admin_popups', 'GDC Admin Alerts',
    description: 'High-priority pop-up alerts for GDC Admin Store Staff',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static Future<void> initialize() async {
    // Request permission (Android 13+, iOS)
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // Set up local notifications
    await _initLocalNotifications();

    // Subscribe to admin-specific alerts
    await _fcm.subscribeToTopic('admin_alerts');

    // Show notification when app is in foreground
    FirebaseMessaging.onMessage.listen((message) {
      handleMessage(message);
    });
  }

  /// Use this for background isolate initialization
  static Future<void> initializeBackground() async {
    await _initLocalNotifications();
  }

  static Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(const InitializationSettings(android: androidSettings));

    final androidImpl = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.createNotificationChannel(_adminChannel);
  }

  static void handleMessage(RemoteMessage message) {
    // Strict Recipient Filter: Admin app ONLY handles admin messages
    final String recipient = message.data['recipient'] ?? '';
    if (recipient == 'customer') return;

    String? title = message.notification?.title ?? message.data['title'];
    String? body  = message.notification?.body  ?? message.data['body'];

    if (title == null && body == null) return;
    
    final String displayTitle = title?.startsWith('🛡️ GDC Admin') == true
        ? title!
        : '🛡️ GDC Admin • ${title ?? 'Alert'}';

    showSmsNotificationPopUp(
      id: message.hashCode,
      title: displayTitle,
      body: body ?? '',
    );
  }

  // ── HEADS-UP ADMIN POP-UP NOTIFICATIONS ────────────────────────────────────

  static Future<void> showSmsNotificationPopUp({
    required String title,
    required String body,
    int? id,
  }) async {
    try {
      final String formattedTitle = title.startsWith('🛡️ GDC Admin') 
          ? title 
          : '🛡️ GDC Admin • $title';

      await _local.show(
        id ?? DateTime.now().millisecondsSinceEpoch.remainder(100000),
        formattedTitle,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'gdc_admin_popups', 'GDC Admin Alerts',
            channelDescription: 'High-priority pop-up alerts for GDC Admin Store Staff',
            importance: Importance.max,
            priority: Priority.high,
            visibility: NotificationVisibility.public,
            fullScreenIntent: false,
            icon: '@mipmap/ic_launcher',
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Local Notification Error: $e');
    }
  }

  // ── ADMIN ALERTS (Shown locally on Admin device) ───────────────────────────

  static Future<void> showRefundRequestAlert(String transactionId, String customer) =>
      showSmsNotificationPopUp(
        id: transactionId.hashCode + 2,
        title: 'New Refund Request 💸',
        body: 'Customer $customer requested a refund for sale #$transactionId.',
      );

  static Future<void> showLowStockSupplierAlert(String productName, String supplierName, String phone) =>
      showSmsNotificationPopUp(
        id: productName.hashCode + 3,
        title: 'Low Stock Alert 📞',
        body: '$productName is low in stock! Contact $supplierName at $phone.',
      );

  static Future<void> showPaymentReceivedAlert(String orderId, double amount, String customerName) =>
      showSmsNotificationPopUp(
        id: orderId.hashCode + 4,
        title: 'Payment Received 💰',
        body: 'Payment of ₱${amount.toStringAsFixed(2)} confirmed for order $orderId from $customerName.',
      );

  static Future<void> showNewPreOrderAlert(String orderId, String customerName, double total) =>
      showSmsNotificationPopUp(
        id: orderId.hashCode + 5,
        title: 'New Pre-Order Received 🛍️',
        body: 'Customer $customerName placed order #$orderId (₱${total.toStringAsFixed(2)}).',
      );

  // ── CUSTOMER DISPATCHERS (ONLY UPDATE DISPATCH LOGS, DO NOT POP UP ON ADMIN DEVICE) ─

  static String _getTopic(String email) => 
      'customer_${email.toLowerCase().replaceAll('.', '_').replaceAll('@', '_')}';

  static Future<void> sendOrderUpdate({
    required String email,
    required String orderId,
    required String status,
    required String title,
    required String body,
  }) async {
    final topic = _getTopic(email);
    
    if (kDebugMode) {
      print('FCM Dispatch to Customer Topic: $topic');
      print('Payload: { "recipient": "customer", "orderId": "$orderId", "status": "$status" }');
      print('Title: $title | Body: $body');
    }

    // NOTE: Does NOT call local showSmsNotificationPopUp on Admin device!
    // Customer app receives state update via Firestore snapshot listener or FCM payload.
  }

  static Future<void> sendOrderReady(String orderId, String email) async {
    await sendOrderUpdate(
      email: email,
      orderId: orderId,
      status: 'ready',
      title: '📦 Order Ready for Pickup!',
      body: 'Your order $orderId is packed and ready. Visit GDC Store to collect.',
    );
  }

  static Future<void> sendOrderCollected(String orderId, String email) async {
    await sendOrderUpdate(
      email: email,
      orderId: orderId,
      status: 'collected',
      title: '✅ Order Collected!',
      body: 'Thank you for shopping! Your order $orderId has been marked as collected.',
    );
  }

  static Future<void> sendRefundUpdate(String transactionId, String email, bool approved) async {
    await sendOrderUpdate(
      email: email,
      orderId: transactionId,
      status: approved ? 'refunded' : 'refundRejected',
      title: approved ? '💸 Refund Approved' : '❌ Refund Rejected',
      body: approved 
          ? 'Your refund for #$transactionId has been approved and processed.' 
          : 'Your refund request for #$transactionId was not approved.',
    );
  }

  static Future<void> sendOrderAutoCancelled(String orderId, String email) async {
    await sendOrderUpdate(
      email: email,
      orderId: orderId,
      status: 'cancelled',
      title: '⚠️ Order Expired/Cancelled',
      body: 'Your order $orderId was cancelled as it was not collected within the timeframe.',
    );
  }

  static Future<void> schedulePerishableReminder(String id, String orderId) async {
    if (kDebugMode) {
      print('Target Customer Reminder Scheduled for $orderId');
    }
  }

  static Future<void> sendBackInStock(String productName, String userEmail) async {
    if (kDebugMode) {
      print('Target Customer Back-In-Stock Alert for $productName ($userEmail)');
    }
  }
}
