import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Messaging service handling Brevo transactional email, Traccar/ngrok SMS OTP,
/// and automated customer order status notifications.
class AdminMessagingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? _lastBrevoError;

  /// Singleton instance
  static final AdminMessagingService _instance = AdminMessagingService._internal();
  factory AdminMessagingService() => _instance;
  AdminMessagingService._internal();

  /// Environment key getters with safe auto-initialization & fallbacks
  Future<void> _ensureEnvLoaded() async {
    if (!dotenv.isInitialized) {
      try {
        await dotenv.load(fileName: "assets/.env");
      } catch (e) {
        try {
          await dotenv.load(fileName: ".env");
        } catch (_) {}
      }
    }
  }

  String get _brevoApiKey {
    if (dotenv.isInitialized) {
      return dotenv.env['BREVO_API_KEY'] ?? '';
    }
    return '';
  }

  String get _brevoSenderEmail {
    if (dotenv.isInitialized) {
      return dotenv.env['BREVO_SENDER_EMAIL'] ?? 'gdcstore.ph@gmail.com';
    }
    return 'gdcstore.ph@gmail.com';
  }

  String get _traccarGatewayUrl {
    if (dotenv.isInitialized) {
      return dotenv.env['TRACCAR_GATEWAY_URL'] ?? '';
    }
    return '';
  }

  String get _traccarToken {
    if (dotenv.isInitialized) {
      return dotenv.env['TRACCAR_TOKEN'] ?? '';
    }
    return '';
  }

  /// Sends a transactional email using Brevo HTTP API (v3/smtp/email).
  Future<bool> sendBrevoEmail({
    required String toEmail,
    required String subject,
    required String htmlContent,
    String? recipientName,
  }) async {
    await _ensureEnvLoaded();
    final apiKey = _brevoApiKey;
    final senderEmail = _brevoSenderEmail;

    if (apiKey.isEmpty) {
      debugPrint('[AdminMessagingService] BREVO_API_KEY is missing from environment.');
      return false;
    }

    try {
      final url = Uri.parse('https://api.brevo.com/v3/smtp/email');
      final headers = {
        'accept': 'application/json',
        'api-key': apiKey,
        'content-type': 'application/json',
      };

      final body = jsonEncode({
        'sender': {
          'name': 'GDC Store',
          'email': senderEmail,
        },
        'to': [
          {
            'email': toEmail.trim(),
            if (recipientName != null && recipientName.trim().isNotEmpty)
              'name': recipientName.trim(),
          }
        ],
        'subject': subject,
        'htmlContent': htmlContent,
      });

      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _lastBrevoError = null;
        debugPrint('[AdminMessagingService] Brevo Email sent to $toEmail [${response.statusCode}]');
        return true;
      } else {
        _lastBrevoError = 'Brevo [${response.statusCode}]: ${response.body}';
        debugPrint('[AdminMessagingService] Brevo Email failed [${response.statusCode}]: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[AdminMessagingService] Exception sending Brevo email: $e');
      return false;
    }
  }

  /// Sends an SMS via Traccar SMS Gateway (routed through ngrok public tunnel).
  Future<bool> sendTraccarSms({
    required String toPhone,
    required String message,
  }) async {
    await _ensureEnvLoaded();
    final gatewayUrl = _traccarGatewayUrl;
    final token = _traccarToken;

    if (gatewayUrl.isEmpty || token.isEmpty) {
      debugPrint('[AdminMessagingService] Traccar gateway URL or token missing.');
      return false;
    }

    try {
      final cleanUrl = gatewayUrl.endsWith('/') ? gatewayUrl.substring(0, gatewayUrl.length - 1) : gatewayUrl;
      final uri = Uri.parse(cleanUrl);

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': token,
        'ngrok-skip-browser-warning': 'true',
      };

      final body = jsonEncode({
        'to': toPhone.trim(),
        'message': message,
      });

      final response = await http.post(uri, headers: headers, body: body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[AdminMessagingService] Traccar SMS sent to $toPhone [${response.statusCode}]');
        return true;
      } else {
        debugPrint('[AdminMessagingService] Traccar SMS failed [${response.statusCode}]: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[AdminMessagingService] Exception sending Traccar SMS: $e');
      return false;
    }
  }

  /// Generates a 6-digit random OTP, stores it in Firestore `otp_requests/{contactMethod}` for 5 minutes,
  /// and sends it via Brevo Email or Traccar SMS.
  Future<Map<String, dynamic>> sendAdminOtp({
    required String contactMethod,
    required bool isEmail,
  }) async {
    await _ensureEnvLoaded();
    final sanitizedContact = contactMethod.trim();
    if (sanitizedContact.isEmpty) {
      return {'success': false, 'message': 'Contact method cannot be empty.'};
    }

    // Generate random 6-digit OTP code
    final random = Random.secure();
    final otp = (100000 + random.nextInt(900000)).toString();

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(minutes: 5));

    try {
      // Save record in Firestore under otp_requests/{contactMethod}
      await _db.collection('otp_requests').doc(sanitizedContact).set({
        'code': otp,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'attempts': 0,
        'isEmail': isEmail,
        'contactMethod': sanitizedContact,
      });

      bool sent = false;
      if (isEmail) {
        final htmlContent = '''
<div style="font-family: Arial, sans-serif; padding: 24px; background-color: #f4f6f9;">
  <div style="max-width: 500px; margin: 0 auto; background-color: #ffffff; border-radius: 12px; padding: 32px; border: 1px solid #e2e8f0;">
    <h2 style="color: #1a202c; margin-top: 0;">GDC Store Admin Verification</h2>
    <p style="color: #4a5568; font-size: 15px;">Use the following 6-digit OTP code to verify your admin identity:</p>
    <div style="text-align: center; margin: 28px 0;">
      <span style="font-size: 36px; font-weight: bold; letter-spacing: 6px; color: #2563eb; background-color: #eff6ff; padding: 12px 24px; border-radius: 8px; border: 1px dashed #bfdbfe; display: inline-block;">
        $otp
      </span>
    </div>
    <p style="color: #718096; font-size: 13px;">This verification code is valid for <strong>5 minutes</strong>. Do not share this code with anyone.</p>
    <hr style="border: 0; border-top: 1px solid #edf2f7; margin: 24px 0;" />
    <p style="color: #a0aec0; font-size: 12px; margin-bottom: 0;">GDC Sari-Sari Store Management System</p>
  </div>
</div>
''';
        sent = await sendBrevoEmail(
          toEmail: sanitizedContact,
          subject: 'GDC Store - Admin OTP Verification Code',
          htmlContent: htmlContent,
        );
      } else {
        final smsMessage = 'GDC Store: Your admin OTP verification code is $otp. Valid for 5 minutes.';
        sent = await sendTraccarSms(
          toPhone: sanitizedContact,
          message: smsMessage,
        );
      }

      if (sent) {
        return {
          'success': true,
          'message': 'OTP sent successfully to $sanitizedContact.',
          'otp': otp,
        };
      } else {
        if (isEmail && _lastBrevoError != null && _lastBrevoError!.contains('API Key is not enabled')) {
          return {
            'success': false,
            'message': 'Brevo API Key is not enabled on Brevo Dashboard (Error 401). Please activate Transactional Email on app.brevo.com or use SMS OTP.',
          };
        }
        return {
          'success': false,
          'message': 'Failed to deliver OTP via ${isEmail ? "Email" : "SMS"}. Please try again.',
        };
      }
    } catch (e) {
      debugPrint('[AdminMessagingService] Error sending OTP: $e');
      return {
        'success': false,
        'message': 'Error sending OTP: ${e.toString()}',
      };
    }
  }

  /// Validates OTP code against Firestore `otp_requests/{contactMethod}`, checks expiration and max attempts (5),
  /// and deletes the record on success.
  Future<Map<String, dynamic>> verifyAdminOtp({
    required String contactMethod,
    required String enteredCode,
  }) async {
    final sanitizedContact = contactMethod.trim();
    final sanitizedCode = enteredCode.trim();

    if (sanitizedContact.isEmpty || sanitizedCode.isEmpty) {
      return {'success': false, 'message': 'Please enter the 6-digit verification code.'};
    }

    try {
      final docRef = _db.collection('otp_requests').doc(sanitizedContact);
      final docSnap = await docRef.get();

      if (!docSnap.exists) {
        return {
          'success': false,
          'message': 'No pending OTP request found for $sanitizedContact. Please request a new code.',
        };
      }

      final data = docSnap.data()!;
      final storedCode = data['code']?.toString() ?? '';
      final Timestamp? expiresAtTs = data['expiresAt'] as Timestamp?;
      final int attempts = (data['attempts'] as num? ?? 0).toInt();

      // Check max attempts
      if (attempts >= 5) {
        return {
          'success': false,
          'message': 'Maximum verification attempts exceeded (5/5). Please request a new OTP code.',
        };
      }

      // Check expiration
      if (expiresAtTs != null) {
        final expiresAt = expiresAtTs.toDate();
        if (DateTime.now().isAfter(expiresAt)) {
          return {
            'success': false,
            'message': 'OTP verification code has expired. Please request a new code.',
          };
        }
      }

      // Verify code
      if (storedCode == sanitizedCode) {
        // Success: delete OTP request record
        await docRef.delete();
        return {
          'success': true,
          'message': 'OTP code verified successfully!',
        };
      } else {
        final newAttempts = attempts + 1;
        await docRef.update({
          'attempts': FieldValue.increment(1),
        });

        final remaining = 5 - newAttempts;
        if (remaining <= 0) {
          return {
            'success': false,
            'message': 'Invalid OTP code. Maximum attempts reached. Please request a new code.',
          };
        }
        return {
          'success': false,
          'message': 'Invalid OTP code. $remaining ${remaining == 1 ? "attempt" : "attempts"} remaining.',
        };
      }
    } catch (e) {
      debugPrint('[AdminMessagingService] Error verifying OTP: $e');
      return {
        'success': false,
        'message': 'Error during OTP verification: ${e.toString()}',
      };
    }
  }

  /// Sends automated Email & SMS notifications to customers when the Admin updates an order's status
  /// (e.g., "GDC Store: Your pre-order #GDC-1024 status is now $newStatus!").
  Future<void> sendCustomerOrderStatusNotification({
    required String customerEmail,
    required String customerPhone,
    required String orderId,
    required String newStatus,
  }) async {
    final statusDisplay = newStatus.toUpperCase();
    final messageText = 'GDC Store: Your pre-order #$orderId status is now $newStatus!';

    // Send SMS via Traccar if customer phone is present
    if (customerPhone.trim().isNotEmpty) {
      sendTraccarSms(
        toPhone: customerPhone.trim(),
        message: messageText,
      ).catchError((e) {
        debugPrint('[AdminMessagingService] Error sending customer SMS: $e');
        return false;
      });
    }

    // Send Email via Brevo if customer email is present
    if (customerEmail.trim().isNotEmpty) {
      final html = '''
<div style="font-family: Arial, sans-serif; padding: 24px; background-color: #f8fafc;">
  <div style="max-width: 550px; margin: 0 auto; background-color: #ffffff; border-radius: 12px; padding: 32px; border: 1px solid #e2e8f0; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);">
    <h2 style="color: #0f172a; margin-top: 0;">GDC Store - Order Update</h2>
    <p style="color: #334155; font-size: 15px;">Your pre-order status has been updated:</p>
    <div style="background-color: #f1f5f9; padding: 16px 20px; border-radius: 8px; margin: 20px 0;">
      <p style="margin: 0 0 8px 0; font-size: 14px; color: #64748b;">Order Number: <strong style="color: #0f172a;">#$orderId</strong></p>
      <p style="margin: 0; font-size: 14px; color: #64748b;">New Status: <strong style="color: #2563eb; font-size: 16px;">$statusDisplay</strong></p>
    </div>
    <p style="color: #475569; font-size: 14px;">Thank you for ordering with GDC Sari-Sari Store!</p>
    <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 24px 0;" />
    <p style="color: #94a3b8; font-size: 12px; margin: 0;">This is an automated notification from GDC Store.</p>
  </div>
</div>
''';
      sendBrevoEmail(
        toEmail: customerEmail.trim(),
        subject: 'GDC Store: Your pre-order #$orderId status is now $newStatus!',
        htmlContent: html,
      ).catchError((e) {
        debugPrint('[AdminMessagingService] Error sending customer email: $e');
        return false;
      });
    }
  }
}
