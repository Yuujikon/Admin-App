import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../models/order.dart';
import '../../models/purchase_order.dart';
import '../../models/receiving_record.dart';
import '../../models/supplier.dart';
import '../../models/daily_resupply_log.dart';
import '../../utils/notice_pdf_printer.dart';
import '../../utils/po_pdf_printer.dart';
import '../../services/audit_log_service.dart';

/// Step-by-step lifecycle stages for PO / Backorder PDF generation and dual-email dispatch.
enum DispatchStage {
  validating,
  generatingPdf,
  sendingEmails,
  completed,
  failed,
}

extension DispatchStageExtension on DispatchStage {
  String get label {
    switch (this) {
      case DispatchStage.validating:
        return 'Validating Data';
      case DispatchStage.generatingPdf:
        return 'Generating PDF';
      case DispatchStage.sendingEmails:
        return 'Sending to Supplier & Store';
      case DispatchStage.completed:
        return 'Dispatched Successfully';
      case DispatchStage.failed:
        return 'Dispatch Attention Needed';
    }
  }
}

/// Structured outcome returned by unified PO / Backorder dual-email dispatch pipelines.
class DocumentDispatchResult {
  final bool validationPassed;
  final SupplierValidationResult? validationResult;
  final bool pdfGenerated;
  final String? pdfError;
  final Uint8List? pdfBytes;
  final String? pdfFileName;
  final String supplierEmail;
  final String storeEmail;
  final bool supplierEmailSent;
  final bool storeCopyEmailSent;
  final String? supplierError;
  final String? storeError;

  const DocumentDispatchResult({
    required this.validationPassed,
    this.validationResult,
    required this.pdfGenerated,
    this.pdfError,
    this.pdfBytes,
    this.pdfFileName,
    required this.supplierEmail,
    required this.storeEmail,
    required this.supplierEmailSent,
    required this.storeCopyEmailSent,
    this.supplierError,
    this.storeError,
  });

  /// True only when validation passed, PDF generated, and BOTH recipients received delivery.
  bool get isFullSuccess =>
      validationPassed &&
      pdfGenerated &&
      supplierEmailSent &&
      storeCopyEmailSent;

  /// True when PDF generated and one of the two recipients succeeded while the other failed.
  bool get isPartialSuccess =>
      validationPassed &&
      pdfGenerated &&
      (supplierEmailSent != storeCopyEmailSent);

  String get summaryMessage {
    if (!validationPassed) {
      return validationResult?.summaryMessage ??
          'Supplier validation failed prior to dispatch.';
    }
    if (!pdfGenerated) {
      return 'PDF generation failed: ${pdfError ?? "Unknown error"}';
    }
    if (isFullSuccess) {
      return 'Document delivered to both Supplier ($supplierEmail) and Store ($storeEmail).';
    }
    if (isPartialSuccess) {
      final succeeded = supplierEmailSent ? 'Supplier' : 'Store Copy';
      final failed = supplierEmailSent ? 'Store Copy' : 'Supplier';
      final err = supplierEmailSent ? storeError : supplierError;
      return '$succeeded delivered, but $failed failed${err != null ? ": $err" : ""}.';
    }
    return 'Delivery failed for both recipients. ${supplierError ?? storeError ?? ""}';
  }
}

/// Messaging service handling Brevo transactional email, Traccar/ngrok SMS OTP,
/// and automated customer order status notifications.
class AdminMessagingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? _lastBrevoError;
  String? _lastSmsError;

  /// Singleton instance
  static final AdminMessagingService _instance =
      AdminMessagingService._internal();
  factory AdminMessagingService() => _instance;
  AdminMessagingService._internal();

  /// Returns the configured store/admin copy email address (loading `.env` if needed).
  Future<String> resolveStoreEmail() async {
    await _ensureEnvLoaded();
    return _brevoSenderEmail.trim();
  }

  /// Synchronous getter for the store/admin copy email address.
  String get storeEmailSync => _brevoSenderEmail.trim();

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
    String? ccEmail,
    String? replyToEmail,
  }) async {
    await _ensureEnvLoaded();
    final apiKey = _brevoApiKey;
    final senderEmail = _brevoSenderEmail;

    if (apiKey.isEmpty) {
      debugPrint(
          '[AdminMessagingService] BREVO_API_KEY is missing from environment.');
      return false;
    }

    try {
      final url = Uri.parse('https://api.brevo.com/v3/smtp/email');
      final headers = {
        'accept': 'application/json',
        'api-key': apiKey,
        'content-type': 'application/json',
      };

      final effectiveCc = (ccEmail ?? senderEmail).trim();
      final effectiveReplyTo = (replyToEmail ?? senderEmail).trim();

      final Map<String, dynamic> bodyMap = {
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
      };

      if (effectiveCc.isNotEmpty &&
          effectiveCc.toLowerCase() != toEmail.trim().toLowerCase()) {
        bodyMap['cc'] = [
          {
            'email': effectiveCc,
            'name': 'GDC Store',
          }
        ];
      }

      if (effectiveReplyTo.isNotEmpty) {
        bodyMap['replyTo'] = {
          'email': effectiveReplyTo,
          'name': 'GDC Store',
        };
      }

      final body = jsonEncode(bodyMap);

      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _lastBrevoError = null;
        debugPrint(
            '[AdminMessagingService] Brevo Email sent to $toEmail [${response.statusCode}]');
        return true;
      } else {
        _lastBrevoError = 'Brevo [${response.statusCode}]: ${response.body}';
        debugPrint(
            '[AdminMessagingService] Brevo Email failed [${response.statusCode}]: ${response.body}');
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
      debugPrint(
          '[AdminMessagingService] Traccar gateway URL or token missing.');
      return false;
    }

    try {
      final cleanUrl = gatewayUrl.endsWith('/')
          ? gatewayUrl.substring(0, gatewayUrl.length - 1)
          : gatewayUrl;
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
        _lastSmsError = null;
        debugPrint(
            '[AdminMessagingService] Traccar SMS sent to $toPhone [${response.statusCode}]');
        return true;
      } else {
        final bodyText = response.body;
        if (response.statusCode == 502 ||
            bodyText.contains('8012') ||
            bodyText.contains('connection refused') ||
            bodyText.contains('upstream web service')) {
          _lastSmsError =
              'Traccar Gateway Service (localhost:8082) is offline or unreachable via ngrok (HTTP 502 Bad Gateway).';
        } else {
          _lastSmsError =
              'Traccar SMS failed [${response.statusCode}]: $bodyText';
        }
        debugPrint(
            '[AdminMessagingService] Traccar SMS failed [${response.statusCode}]: $bodyText');
        return false;
      }
    } catch (e) {
      _lastSmsError = 'Exception sending Traccar SMS: $e';
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
        final smsMessage =
            'GDC Store: Your admin OTP verification code is $otp. Valid for 5 minutes.';
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
        if (isEmail &&
            _lastBrevoError != null &&
            _lastBrevoError!.contains('API Key is not enabled')) {
          return {
            'success': false,
            'message':
                'Brevo API Key is not enabled on Brevo Dashboard (Error 401). Please activate Transactional Email on app.brevo.com or use SMS OTP.',
          };
        }
        if (!isEmail &&
            _lastSmsError != null &&
            _lastSmsError!.contains('localhost:8082')) {
          return {
            'success': false,
            'message':
                'SMS Gateway service (localhost:8082) is offline or unreachable via ngrok tunnel (HTTP 502 Bad Gateway). Please start the Traccar SMS Gateway service or use Email OTP.',
          };
        }
        return {
          'success': false,
          'message':
              'Failed to deliver OTP via ${isEmail ? "Email" : "SMS"}. Please try again.',
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

  /// Sends a custom branded Password Reset email via Brevo.
  Future<bool> sendBrandedPasswordResetEmail({
    required String toEmail,
  }) async {
    final sanitizedEmail = toEmail.trim();
    if (sanitizedEmail.isEmpty) return false;

    final html = '''
<div style="font-family: Arial, sans-serif; padding: 32px; background-color: #f8fafc;">
  <div style="max-width: 520px; margin: 0 auto; background-color: #ffffff; border-radius: 16px; padding: 36px; border: 1px solid #e2e8f0; box-shadow: 0 4px 12px rgba(0, 0, 0, 0.05);">
    <div style="text-align: center; margin-bottom: 24px;">
      <h2 style="color: #C07038; margin: 0; font-size: 24px; font-weight: bold; letter-spacing: 1px;">GDC SARI-SARI STORE</h2>
      <p style="color: #64748b; font-size: 13px; margin-top: 4px;">Staff & Admin Account Management</p>
    </div>
    
    <hr style="border: 0; border-top: 1px solid #f1f5f9; margin: 20px 0;" />

    <p style="color: #1e293b; font-size: 15px; line-height: 1.6;">Hello,</p>
    <p style="color: #334155; font-size: 15px; line-height: 1.6;">
      We received a request to reset the password for your GDC Store staff account (<strong>$sanitizedEmail</strong>).
    </p>

    <div style="background-color: #fbf8f2; border: 1px solid #f3d7c3; border-radius: 10px; padding: 20px; margin: 24px 0; text-align: center;">
      <p style="margin: 0 0 8px 0; color: #C07038; font-size: 14px; font-weight: bold;">Password Reset Requested</p>
      <p style="margin: 0; color: #475569; font-size: 13px;">Check your inbox for the official reset authorization email, or use your 6-digit OTP verification option on the login portal.</p>
    </div>

    <p style="color: #64748b; font-size: 13px; line-height: 1.5; margin-top: 24px;">
      If you did not request a password reset, you can safely ignore this email. Your password will remain secure and unchanged.
    </p>

    <hr style="border: 0; border-top: 1px solid #f1f5f9; margin: 24px 0;" />

    <p style="color: #94a3b8; font-size: 12px; text-align: center; margin: 0;">
      GDC Sari-Sari Store Management System
    </p>
  </div>
</div>
''';

    return await sendBrevoEmail(
      toEmail: sanitizedEmail,
      subject: 'GDC Store - Password Reset Request',
      htmlContent: html,
    );
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
      return {
        'success': false,
        'message': 'Please enter the 6-digit verification code.'
      };
    }

    try {
      final docRef = _db.collection('otp_requests').doc(sanitizedContact);
      final docSnap = await docRef.get();

      if (!docSnap.exists) {
        return {
          'success': false,
          'message':
              'No pending OTP request found for $sanitizedContact. Please request a new code.',
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
          'message':
              'Maximum verification attempts exceeded (5/5). Please request a new OTP code.',
        };
      }

      // Check expiration
      if (expiresAtTs != null) {
        final expiresAt = expiresAtTs.toDate();
        if (DateTime.now().isAfter(expiresAt)) {
          return {
            'success': false,
            'message':
                'OTP verification code has expired. Please request a new code.',
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
            'message':
                'Invalid OTP code. Maximum attempts reached. Please request a new code.',
          };
        }
        return {
          'success': false,
          'message':
              'Invalid OTP code. $remaining ${remaining == 1 ? "attempt" : "attempts"} remaining.',
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
    final messageText =
        'GDC Store: Your pre-order #$orderId status is now $newStatus!';

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
        subject:
            'GDC Store: Your pre-order #$orderId status is now $newStatus!',
        htmlContent: html,
      ).catchError((e) {
        debugPrint('[AdminMessagingService] Error sending customer email: $e');
        return false;
      });
    }
  }

  /// Sends a branded transactional email notification to a customer or staff member via Brevo.
  Future<bool> sendNotification({
    required String recipientEmail,
    required String title,
    required String body,
  }) async {
    if (recipientEmail.trim().isEmpty) return false;

    final htmlContent = '''
<div style="font-family: Arial, sans-serif; padding: 24px; background-color: #f8fafc;">
  <div style="max-width: 550px; margin: 0 auto; background-color: #ffffff; border-radius: 12px; padding: 32px; border: 1px solid #e2e8f0; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);">
    <h2 style="color: #0f172a; margin-top: 0;">$title</h2>
    <p style="color: #334155; font-size: 15px; line-height: 1.6;">$body</p>
    <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 24px 0;" />
    <p style="color: #94a3b8; font-size: 12px; margin: 0;">GDC Sari-Sari Store Management System</p>
  </div>
</div>
''';

    return await sendBrevoEmail(
      toEmail: recipientEmail.trim(),
      subject: title,
      htmlContent: htmlContent,
    );
  }

  /// Sends an itemized digital purchase receipt email to a customer via Brevo upon successful pre-order pickup completion.
  Future<bool> sendDigitalReceiptEmail({
    required String customerEmail,
    required String customerName,
    required String orderId,
    required List<CartItem> items,
    required double total,
    required String paymentMethod,
    double cashTendered = 0,
    double changeGiven = 0,
    DateTime? completedAt,
  }) async {
    final sanitizedEmail = customerEmail.trim();
    if (sanitizedEmail.isEmpty) return false;

    final dateStr = DateFormat('MMM d, yyyy • h:mm a')
        .format(completedAt ?? DateTime.now());

    String formatPeso(double amount) => '₱${amount.toStringAsFixed(2)}';

    final StringBuffer itemsRowsHtml = StringBuffer();
    for (final item in items) {
      final String variantText =
          (item.variantName != null && item.variantName!.isNotEmpty)
              ? ' (${item.variantName})'
              : '';
      final double lineTotal = item.price * item.qty;

      itemsRowsHtml.write('''
<tr style="border-bottom: 1px solid #f1f5f9;">
  <td style="padding: 10px 0; color: #1e293b; font-size: 14px;">
    <strong>${item.qty}x</strong> ${item.name}$variantText
  </td>
  <td style="padding: 10px 0; color: #64748b; font-size: 13px; text-align: center;">
    ${formatPeso(item.price)}
  </td>
  <td style="padding: 10px 0; color: #0f172a; font-size: 14px; font-weight: bold; text-align: right;">
    ${formatPeso(lineTotal)}
  </td>
</tr>
''');
    }

    final bool isCash = paymentMethod.toUpperCase() == 'CASH';

    final htmlContent = '''
<div style="font-family: Arial, sans-serif; padding: 24px; background-color: #f8fafc;">
  <div style="max-width: 580px; margin: 0 auto; background-color: #ffffff; border-radius: 16px; padding: 36px; border: 1px solid #e2e8f0; box-shadow: 0 4px 12px rgba(0,0,0,0.05);">
    
    <!-- Store Header -->
    <div style="text-align: center; margin-bottom: 24px;">
      <h2 style="color: #047857; margin: 0; font-size: 22px; font-weight: bold; letter-spacing: 1px;">GDC SARI-SARI STORE</h2>
      <p style="color: #64748b; font-size: 13px; margin: 4px 0 0 0;">Official Digital Purchase Receipt</p>
    </div>
    
    <div style="background-color: #ecfdf5; border: 1px solid #a7f3d0; border-radius: 10px; padding: 14px 18px; margin-bottom: 24px;">
      <p style="margin: 0; color: #047857; font-size: 14px; font-weight: bold; text-align: center;">
        ✓ PRE-ORDER FULFILLMENT COMPLETED & VERIFIED
      </p>
    </div>

    <!-- Receipt Meta Details -->
    <table style="width: 100%; margin-bottom: 20px; font-size: 13px; color: #475569;">
      <tr>
        <td style="padding: 4px 0;"><strong>Order ID:</strong> #$orderId</td>
        <td style="padding: 4px 0; text-align: right;"><strong>Date:</strong> $dateStr</td>
      </tr>
      <tr>
        <td style="padding: 4px 0;"><strong>Customer:</strong> ${customerName.isNotEmpty ? customerName : 'Valued Customer'}</td>
        <td style="padding: 4px 0; text-align: right;"><strong>Payment:</strong> <span style="background-color: #e0f2fe; color: #0369a1; padding: 2px 8px; border-radius: 6px; font-weight: bold;">$paymentMethod</span></td>
      </tr>
    </table>

    <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 16px 0;" />

    <!-- Purchased Items Table -->
    <table style="width: 100%; border-collapse: collapse; margin-bottom: 20px;">
      <thead>
        <tr style="border-bottom: 2px solid #e2e8f0; text-align: left; color: #64748b; font-size: 12px; text-transform: uppercase;">
          <th style="padding: 8px 0; width: 60%;">Item</th>
          <th style="padding: 8px 0; width: 20%; text-align: center;">Price</th>
          <th style="padding: 8px 0; width: 20%; text-align: right;">Total</th>
        </tr>
      </thead>
      <tbody>
        $itemsRowsHtml
      </tbody>
    </table>

    <!-- Totals Summary Box -->
    <div style="background-color: #f8fafc; border-radius: 10px; padding: 16px; margin-top: 16px;">
      <table style="width: 100%; font-size: 14px;">
        <tr>
          <td style="color: #64748b; padding: 4px 0;">Total Amount Paid:</td>
          <td style="color: #047857; font-weight: 900; font-size: 20px; text-align: right;">${formatPeso(total)}</td>
        </tr>
        ${isCash && cashTendered > 0 ? '''
        <tr>
          <td style="color: #64748b; padding: 4px 0; font-size: 13px;">Cash Tendered:</td>
          <td style="color: #334155; font-size: 13px; text-align: right;">${formatPeso(cashTendered)}</td>
        </tr>
        <tr>
          <td style="color: #64748b; padding: 4px 0; font-size: 13px;">Change Returned:</td>
          <td style="color: #16a34a; font-size: 13px; font-weight: bold; text-align: right;">${formatPeso(changeGiven)}</td>
        </tr>
        ''' : ''}
      </table>
    </div>

    <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 28px 0 20px 0;" />

    <!-- Footer -->
    <div style="text-align: center; color: #94a3b8; font-size: 12px;">
      <p style="margin: 0 0 4px 0;">Thank you for shopping at GDC Sari-Sari Store!</p>
      <p style="margin: 0;">Please keep this digital receipt for your records.</p>
    </div>
  </div>
</div>
''';

    return await sendBrevoEmail(
      toEmail: sanitizedEmail,
      subject: 'GDC Store - Official Purchase Receipt for Order #$orderId',
      htmlContent: htmlContent,
      recipientName: customerName,
    );
  }

  /// Escapes HTML special characters so user-entered supplier metadata renders safely in email clients.
  static String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// Renders the standardized, Single-Source-of-Truth Supplier Details HTML card
  /// embedded identically in BOTH the Supplier email and the Store/Admin Copy email.
  static String buildValidatedSupplierHtmlSection(SupplierSnapshot snapshot) {
    final name = _escapeHtml(snapshot.supplierName.trim());
    final contact = _escapeHtml(snapshot.contactPerson.trim());
    final email = _escapeHtml(snapshot.email.trim());
    final phone = _escapeHtml(snapshot.phone.trim());
    final address = _escapeHtml(snapshot.address.trim());
    final tin = _escapeHtml(snapshot.tin.trim());
    final paymentTerms = _escapeHtml(snapshot.paymentTerms.trim());

    String row(String label, String value) {
      if (value.isEmpty) return '';
      return '''
<tr>
  <td style="padding: 3px 0; width: 34%; color: #64748b; font-size: 12.5px; vertical-align: top;"><strong>$label:</strong></td>
  <td style="padding: 3px 0; color: #0f172a; font-size: 12.5px; vertical-align: top;">$value</td>
</tr>
''';
    }

    return '''
<div style="background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 10px; padding: 14px 16px; margin: 16px 0;">
  <p style="margin: 0 0 8px 0; font-size: 11px; font-weight: bold; letter-spacing: 0.6px; text-transform: uppercase; color: #0f766e;">
    Vendor / Supplier Details
  </p>
  <p style="margin: 0 0 8px 0; font-size: 15px; font-weight: bold; color: #0f172a;">$name</p>
  <table style="width: 100%; border-collapse: collapse;">
    ${row('Contact Person', contact)}
    ${row('Email', email)}
    ${row('Phone', phone)}
    ${row('Address', address)}
    ${row('TIN / Business ID', tin)}
    ${row('Payment Terms', paymentTerms)}
  </table>
</div>
''';
  }

  /// Internal single-recipient Brevo transactional email sender with PDF attachment
  /// returning explicit success status and error diagnostics.
  Future<({bool sent, String? error})> _sendSingleBrevoPdfEmail({
    required String toEmail,
    required String subject,
    required String htmlContent,
    required String pdfFileName,
    required Uint8List pdfBytes,
    String? recipientName,
    String? ccEmail,
    String? replyToEmail,
  }) async {
    await _ensureEnvLoaded();
    final apiKey = _brevoApiKey;
    final senderEmail = _brevoSenderEmail.trim();

    if (apiKey.isEmpty) {
      const msg = 'BREVO_API_KEY is missing from environment.';
      _lastBrevoError = msg;
      debugPrint('[AdminMessagingService] $msg');
      return (sent: false, error: msg);
    }

    final cleanTo = toEmail.trim();
    if (cleanTo.isEmpty) {
      const msg = 'Recipient email address is empty.';
      return (sent: false, error: msg);
    }

    try {
      final url = Uri.parse('https://api.brevo.com/v3/smtp/email');
      final headers = {
        'accept': 'application/json',
        'api-key': apiKey,
        'content-type': 'application/json',
      };

      final base64Pdf = base64Encode(pdfBytes);
      final cleanCc = (ccEmail ?? '').trim();
      final cleanReplyTo = (replyToEmail ?? senderEmail).trim();

      final Map<String, dynamic> bodyMap = {
        'sender': {
          'name': 'GDC Store Procurement',
          'email': senderEmail,
        },
        'to': [
          {
            'email': cleanTo,
            if (recipientName != null && recipientName.trim().isNotEmpty)
              'name': recipientName.trim(),
          }
        ],
        'subject': subject,
        'htmlContent': htmlContent,
        'attachment': [
          {
            'name': pdfFileName,
            'content': base64Pdf,
          }
        ],
      };

      // Guard against Brevo HTTP 400 when cc duplicates the primary recipient
      if (cleanCc.isNotEmpty &&
          cleanCc.toLowerCase() != cleanTo.toLowerCase()) {
        bodyMap['cc'] = [
          {
            'email': cleanCc,
            'name': 'GDC Store Procurement',
          }
        ];
      }

      if (cleanReplyTo.isNotEmpty) {
        bodyMap['replyTo'] = {
          'email': cleanReplyTo,
          'name': 'GDC Store Procurement',
        };
      }

      final response = await http
          .post(url, headers: headers, body: jsonEncode(bodyMap))
          .timeout(const Duration(seconds: 25));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _lastBrevoError = null;
        debugPrint(
            '[AdminMessagingService] Brevo Email with PDF sent to $cleanTo [${response.statusCode}]');
        return (sent: true, error: null);
      } else {
        final err = 'Brevo [${response.statusCode}]: ${response.body}';
        _lastBrevoError = err;
        debugPrint('[AdminMessagingService] Brevo Email with PDF failed: $err');
        return (sent: false, error: err);
      }
    } catch (e) {
      final err = 'Network/Dispatch error: $e';
      _lastBrevoError = err;
      debugPrint(
          '[AdminMessagingService] Exception sending Brevo email with PDF: $e');
      return (sent: false, error: err);
    }
  }

  /// Sends a transactional email with a PDF attachment using Brevo HTTP API (v3/smtp/email).
  Future<bool> sendSupplierEmailWithPdf({
    required String toEmail,
    required String subject,
    required String htmlContent,
    required String pdfFileName,
    required Uint8List pdfBytes,
    String? recipientName,
    String? ccEmail,
    String? replyToEmail,
  }) async {
    final result = await _sendSingleBrevoPdfEmail(
      toEmail: toEmail,
      subject: subject,
      htmlContent: htmlContent,
      pdfFileName: pdfFileName,
      pdfBytes: pdfBytes,
      recipientName: recipientName,
      ccEmail: ccEmail ?? _brevoSenderEmail,
      replyToEmail: replyToEmail ?? _brevoSenderEmail,
    );
    return result.sent;
  }

  /// Dispatches the exact same validated HTML payload & PDF attachment independently
  /// to BOTH the Supplier Email and the Store/Admin Copy Email so both recipients receive
  /// 100% identical supplier metadata, identical PDF bytes, and individual delivery tracking.
  Future<DocumentDispatchResult> _dispatchDualEmailWithPdf({
    required SupplierSnapshot snapshot,
    required String subject,
    required String htmlContent,
    required String pdfFileName,
    required Uint8List pdfBytes,
    String? storeEmailOverride,
  }) async {
    final String supplierEmail = snapshot.email.trim();
    final String storeEmail =
        ((storeEmailOverride != null && storeEmailOverride.trim().isNotEmpty)
                ? storeEmailOverride
                : await resolveStoreEmail())
            .trim();

    // 1. Dispatch to Supplier (replyTo routed to Store Email)
    final supplierOutcome = await _sendSingleBrevoPdfEmail(
      toEmail: supplierEmail,
      recipientName: snapshot.supplierName,
      subject: subject,
      htmlContent: htmlContent,
      pdfFileName: pdfFileName,
      pdfBytes: pdfBytes,
      replyToEmail: storeEmail,
    );

    // 2. Dispatch identical metadata & identical PDF bytes to Store/Admin Copy
    final storeOutcome = storeEmail.isNotEmpty
        ? await _sendSingleBrevoPdfEmail(
            toEmail: storeEmail,
            recipientName: 'GDC Store Procurement (Admin Copy)',
            subject: '[STORE COPY] $subject',
            htmlContent: htmlContent,
            pdfFileName: pdfFileName,
            pdfBytes: pdfBytes,
            replyToEmail: supplierEmail,
          )
        : (sent: false, error: 'Store/Admin email is not configured.');

    return DocumentDispatchResult(
      validationPassed: true,
      validationResult: const SupplierValidationResult(blockingIssues: []),
      pdfGenerated: true,
      pdfBytes: pdfBytes,
      pdfFileName: pdfFileName,
      supplierEmail: supplierEmail,
      storeEmail: storeEmail,
      supplierEmailSent: supplierOutcome.sent,
      storeCopyEmailSent: storeOutcome.sent,
      supplierError: supplierOutcome.error,
      storeError: storeOutcome.error,
    );
  }

  /// Persists lightweight dual-recipient dispatch log onto `purchase_orders/{po.id}`
  /// and creates a matching Procurement audit trail entry.
  Future<void> _recordDispatchAudit({
    required PurchaseOrder po,
    required SupplierSnapshot snapshot,
    required String noticeTypeKey,
    required String auditAction,
    required String summaryPrefix,
    required DocumentDispatchResult result,
  }) async {
    final metadata = {
      'timestamp': Timestamp.now(),
      'noticeType': noticeTypeKey,
      'poNumber': po.poNumber,
      'supplierEmail': result.supplierEmail,
      'storeEmail': result.storeEmail,
      'supplierEmailSent': result.supplierEmailSent,
      'storeCopyEmailSent': result.storeCopyEmailSent,
      'method': 'brevo_dual_dispatch',
      'status': result.isFullSuccess
          ? 'SUCCESS'
          : (result.isPartialSuccess ? 'PARTIAL' : 'FAILED'),
      if (result.supplierError != null) 'supplierError': result.supplierError,
      if (result.storeError != null) 'storeError': result.storeError,
    };

    try {
      if (po.id.trim().isNotEmpty) {
        await _db.collection('purchase_orders').doc(po.id).set({
          'notificationLogs': FieldValue.arrayUnion([metadata]),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('[AdminMessagingService] Error saving notificationLog: $e');
    }

    try {
      await AuditLogService().logAction(
        module: 'Procurement',
        action: auditAction,
        targetId: po.id,
        targetName: 'PO #${po.poNumber}',
        summary:
            '$summaryPrefix for ${snapshot.supplierName}. Supplier (${result.supplierEmail}): ${result.supplierEmailSent ? "SENT" : "FAILED"}; Store Copy (${result.storeEmail}): ${result.storeCopyEmailSent ? "SENT" : "FAILED"}.',
      );
    } catch (e) {
      debugPrint('[AdminMessagingService] Error saving audit log: $e');
    }
  }

  /// Unified 4-stage pipeline for validating, generating, and dual-dispatching a Purchase Order PDF
  /// to BOTH the Supplier Email and the Store/Admin Copy Email.
  Future<DocumentDispatchResult> dispatchPurchaseOrderWithPdf({
    required PurchaseOrder po,
    Supplier? supplier,
    SupplierSnapshot? supplierSnapshot,
    String? storeEmailOverride,
    void Function(DispatchStage stage)? onStageChanged,
  }) async {
    onStageChanged?.call(DispatchStage.validating);
    final SupplierSnapshot snapshot =
        supplierSnapshot ?? po.resolveSupplierSnapshot(supplier);
    final String storeEmail =
        ((storeEmailOverride != null && storeEmailOverride.trim().isNotEmpty)
                ? storeEmailOverride
                : await resolveStoreEmail())
            .trim();

    final validation = snapshot.validateForDispatch();
    if (!validation.isValid) {
      onStageChanged?.call(DispatchStage.failed);
      return DocumentDispatchResult(
        validationPassed: false,
        validationResult: validation,
        pdfGenerated: false,
        supplierEmail: snapshot.email.trim(),
        storeEmail: storeEmail,
        supplierEmailSent: false,
        storeCopyEmailSent: false,
        supplierError: validation.summaryMessage,
      );
    }

    onStageChanged?.call(DispatchStage.generatingPdf);
    final Uint8List pdfBytes;
    final String pdfFileName = 'Purchase_Order_${po.poNumber}.pdf';
    try {
      pdfBytes = await PoPdfPrinter.generatePoPdf(
        po,
        supplier,
        supplierSnapshot: snapshot,
        enforceValidation: true,
      );
    } catch (e) {
      onStageChanged?.call(DispatchStage.failed);
      return DocumentDispatchResult(
        validationPassed: true,
        validationResult: validation,
        pdfGenerated: false,
        pdfError: e.toString(),
        supplierEmail: snapshot.email.trim(),
        storeEmail: storeEmail,
        supplierEmailSent: false,
        storeCopyEmailSent: false,
      );
    }

    onStageChanged?.call(DispatchStage.sendingEmails);
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final dateStr = DateFormat('MMM dd, yyyy').format(po.orderDate);
    final reqDateStr = po.requestedDeliveryDate != null
        ? DateFormat('MMM dd, yyyy').format(po.requestedDeliveryDate!)
        : 'As soon as possible';

    final StringBuffer itemsHtml = StringBuffer();
    for (int i = 0; i < po.items.length; i++) {
      final item = po.items[i];
      final itemTotal = item.orderedQty * item.unitCost;
      itemsHtml.write('''
<tr style="border-bottom: 1px solid #e2e8f0;">
  <td style="padding: 10px; font-size: 13px; color: #1e293b;">${i + 1}</td>
  <td style="padding: 10px; font-size: 13px; color: #1e293b;"><strong>${_escapeHtml(item.productName)}</strong><br/><span style="font-size: 11px; color: #64748b;">SKU: ${_escapeHtml(item.sku.isNotEmpty ? item.sku : 'N/A')}</span></td>
  <td style="padding: 10px; font-size: 13px; color: #1e293b; text-align: center;"><strong>${item.orderedQty}</strong></td>
  <td style="padding: 10px; font-size: 13px; color: #1e293b; text-align: right;">${currencyFormat.format(item.unitCost)}</td>
  <td style="padding: 10px; font-size: 13px; color: #0f172a; font-weight: bold; text-align: right;">${currencyFormat.format(itemTotal)}</td>
</tr>
''');
    }

    final supplierBlockHtml = buildValidatedSupplierHtmlSection(snapshot);
    final greetingName = snapshot.contactPerson.trim().isNotEmpty
        ? '${_escapeHtml(snapshot.contactPerson.trim())} (${_escapeHtml(snapshot.supplierName)})'
        : _escapeHtml(snapshot.supplierName);

    final htmlContent = '''
<div style="font-family: Arial, sans-serif; padding: 24px; background-color: #f8fafc;">
  <div style="max-width: 620px; margin: 0 auto; background-color: #ffffff; border-radius: 16px; padding: 36px; border: 1px solid #e2e8f0; box-shadow: 0 4px 12px rgba(0,0,0,0.05);">
    <div style="text-align: center; margin-bottom: 24px;">
      <h2 style="color: #0d9488; margin: 0; font-size: 22px; font-weight: bold; letter-spacing: 1px;">GDC SARI-SARI STORE</h2>
      <p style="color: #64748b; font-size: 13px; margin: 4px 0 0 0;">Official Purchase Order</p>
    </div>

    <div style="background-color: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 10px; padding: 14px 18px; margin-bottom: 20px;">
      <p style="margin: 0; color: #166534; font-size: 14px; font-weight: bold; text-align: center;">
        ${po.isBackOrder ? 'BACK-ORDER' : 'PURCHASE ORDER'} #${_escapeHtml(po.poNumber)} SUBMITTED
      </p>
    </div>

    <p style="color: #334155; font-size: 14px; line-height: 1.5;">
      Dear <strong>$greetingName</strong>,
    </p>
    <p style="color: #334155; font-size: 14px; line-height: 1.5;">
      Please find below our official Purchase Order details. The matching PDF document (<strong>${_escapeHtml(pdfFileName)}</strong>) is attached for your records.
    </p>

    $supplierBlockHtml

    <table style="width: 100%; margin: 16px 0; font-size: 13px; color: #475569;">
      <tr>
        <td style="padding: 4px 0;"><strong>PO Number:</strong> #${_escapeHtml(po.poNumber)}</td>
        <td style="padding: 4px 0; text-align: right;"><strong>Order Date:</strong> $dateStr</td>
      </tr>
      <tr>
        <td style="padding: 4px 0;"><strong>Req. Delivery:</strong> $reqDateStr</td>
        <td style="padding: 4px 0; text-align: right;"><strong>Total Items:</strong> ${po.items.length} (${po.totalOrderedQty} units)</td>
      </tr>
      <tr>
        <td style="padding: 4px 0;"><strong>Store Copy:</strong> ${_escapeHtml(storeEmail)}</td>
        <td style="padding: 4px 0; text-align: right;"><strong>Status:</strong> ${_escapeHtml(po.status.displayName)}</td>
      </tr>
    </table>

    <table style="width: 100%; border-collapse: collapse; margin-top: 16px;">
      <thead>
        <tr style="background-color: #0d9488; color: #ffffff; text-align: left; font-size: 12px; text-transform: uppercase;">
          <th style="padding: 10px; width: 8%;">#</th>
          <th style="padding: 10px; width: 42%;">Product</th>
          <th style="padding: 10px; width: 15%; text-align: center;">Qty</th>
          <th style="padding: 10px; width: 17%; text-align: right;">Unit Cost</th>
          <th style="padding: 10px; width: 18%; text-align: right;">Subtotal</th>
        </tr>
      </thead>
      <tbody>
        $itemsHtml
      </tbody>
    </table>

    <div style="background-color: #f8fafc; border-radius: 10px; padding: 16px; margin-top: 20px; border: 1px solid #e2e8f0;">
      <table style="width: 100%; font-size: 14px;">
        <tr>
          <td style="color: #64748b; font-weight: bold;">Grand Total Estimated Value:</td>
          <td style="color: #0d9488; font-weight: 900; font-size: 18px; text-align: right;">${currencyFormat.format(po.totalOrderedValue)}</td>
        </tr>
      </table>
    </div>

    <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 28px 0 20px 0;" />
    <p style="color: #94a3b8; font-size: 12px; text-align: center; margin: 0;">
      Thank you for your partnership.<br/>GDC Sari-Sari Store Procurement Team
    </p>
  </div>
</div>
''';

    final result = await _dispatchDualEmailWithPdf(
      snapshot: snapshot,
      subject: '[GDC SARI-SARI STORE] Purchase Order #${po.poNumber}',
      htmlContent: htmlContent,
      pdfFileName: pdfFileName,
      pdfBytes: pdfBytes,
      storeEmailOverride: storeEmail,
    );

    await _recordDispatchAudit(
      po: po,
      snapshot: snapshot,
      noticeTypeKey: 'purchase_order',
      auditAction: 'SEND_PO_PDF_EMAIL',
      summaryPrefix: 'Purchase Order #${po.poNumber} PDF dual-dispatch',
      result: result,
    );

    onStageChanged?.call(
      result.isFullSuccess ? DispatchStage.completed : DispatchStage.failed,
    );
    return result;
  }

  /// Unified 4-stage pipeline for validating, generating, and dual-dispatching
  /// Backorder Notices, Delivery Confirmations, and Cancellation Notices
  /// to BOTH the Supplier Email and the Store/Admin Copy Email.
  Future<DocumentDispatchResult> dispatchSupplierNoticeWithPdf({
    required PurchaseOrder po,
    Supplier? supplier,
    SupplierSnapshot? supplierSnapshot,
    required NoticeType noticeType,
    String? cancellationReason,
    String? deliveryReceiptNo,
    List<ReceivingItem>? itemsReceived,
    String? storeEmailOverride,
    String actorEmail = 'Admin',
    void Function(DispatchStage stage)? onStageChanged,
  }) async {
    onStageChanged?.call(DispatchStage.validating);
    final SupplierSnapshot snapshot =
        supplierSnapshot ?? po.resolveSupplierSnapshot(supplier);
    final String storeEmail =
        ((storeEmailOverride != null && storeEmailOverride.trim().isNotEmpty)
                ? storeEmailOverride
                : await resolveStoreEmail())
            .trim();

    final validation = snapshot.validateForDispatch();
    if (!validation.isValid) {
      onStageChanged?.call(DispatchStage.failed);
      return DocumentDispatchResult(
        validationPassed: false,
        validationResult: validation,
        pdfGenerated: false,
        supplierEmail: snapshot.email.trim(),
        storeEmail: storeEmail,
        supplierEmailSent: false,
        storeCopyEmailSent: false,
        supplierError: validation.summaryMessage,
      );
    }

    onStageChanged?.call(DispatchStage.generatingPdf);
    final Uint8List pdfBytes;
    final String pdfFileName = '${noticeType.shortCode}_PO_${po.poNumber}.pdf';
    try {
      pdfBytes = await NoticePdfPrinter.generateSupplierNoticePdf(
        po: po,
        supplier: supplier,
        supplierSnapshot: snapshot,
        noticeType: noticeType,
        cancellationReason: cancellationReason,
        itemsReceived: itemsReceived,
        enforceValidation: true,
      );
    } catch (e) {
      onStageChanged?.call(DispatchStage.failed);
      return DocumentDispatchResult(
        validationPassed: true,
        validationResult: validation,
        pdfGenerated: false,
        pdfError: e.toString(),
        supplierEmail: snapshot.email.trim(),
        storeEmail: storeEmail,
        supplierEmailSent: false,
        storeCopyEmailSent: false,
      );
    }

    onStageChanged?.call(DispatchStage.sendingEmails);
    final currencyFormat = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final dateFormat = DateFormat('MMM dd, yyyy');
    final supplierBlockHtml = buildValidatedSupplierHtmlSection(snapshot);
    final greetingName = snapshot.contactPerson.trim().isNotEmpty
        ? '${_escapeHtml(snapshot.contactPerson.trim())} (${_escapeHtml(snapshot.supplierName)})'
        : _escapeHtml(snapshot.supplierName);

    final String backorderId =
        (po.childPoId != null && po.childPoId!.trim().isNotEmpty)
            ? po.childPoId!.trim()
            : 'BO-${po.poNumber}';

    late final String subject;
    late final String htmlContent;
    late final String auditAction;

    if (noticeType == NoticeType.backorder) {
      auditAction = 'SEND_BACKORDER_NOTICE_EMAIL';
      subject =
          '[GDC SARI-SARI STORE] Backorder Notice ($backorderId) - PO #${po.poNumber}';

      final StringBuffer confirmedRowsHtml = StringBuffer();
      final StringBuffer backorderedRowsHtml = StringBuffer();

      for (final item in po.items) {
        if (item.receivedQty > 0) {
          final double acceptedTotal =
              item.receivedQty * item.effectiveUnitCost;
          confirmedRowsHtml.write('''
<tr style="border-bottom: 1px solid #f1f5f9;">
  <td style="padding: 8px 0; color: #1e293b; font-size: 13px;"><strong>${_escapeHtml(item.productName)}</strong><br/><span style="font-size: 11px; color: #64748b;">SKU: ${_escapeHtml(item.sku.isNotEmpty ? item.sku : "N/A")}</span></td>
  <td style="padding: 8px 0; color: #047857; font-size: 13px; font-weight: bold; text-align: center;">${item.receivedQty}</td>
  <td style="padding: 8px 0; color: #0f172a; font-size: 13px; text-align: right;">${currencyFormat.format(acceptedTotal)}</td>
</tr>
''');
        }

        if (item.remainingQty > 0) {
          backorderedRowsHtml.write('''
<tr style="border-bottom: 1px solid #fff7ed;">
  <td style="padding: 8px 0; color: #9a3412; font-size: 13px;"><strong>${_escapeHtml(item.productName)}</strong><br/><span style="font-size: 11px; color: #64748b;">SKU: ${_escapeHtml(item.sku.isNotEmpty ? item.sku : "N/A")}</span></td>
  <td style="padding: 8px 0; color: #c2410c; font-size: 13px; text-align: center;">Ordered: ${item.orderedQty} | Rec: ${item.receivedQty}${item.rejectedQty > 0 ? " | Rej: ${item.rejectedQty}" : ""}</td>
  <td style="padding: 8px 0; color: #dc2626; font-size: 13px; font-weight: bold; text-align: right;">Backordered: ${item.remainingQty} units</td>
</tr>
''');
        }
      }

      htmlContent = '''
<div style="font-family: Arial, sans-serif; padding: 24px; background-color: #f8fafc;">
  <div style="max-width: 620px; margin: 0 auto; background-color: #ffffff; border-radius: 16px; padding: 36px; border: 1px solid #e2e8f0; box-shadow: 0 4px 12px rgba(0,0,0,0.05);">
    <div style="text-align: center; margin-bottom: 24px;">
      <h2 style="color: #c2410c; margin: 0; font-size: 22px; font-weight: bold; letter-spacing: 1px;">GDC SARI-SARI STORE</h2>
      <p style="color: #64748b; font-size: 13px; margin: 4px 0 0 0;">Official Partial Delivery &amp; Back-Order Notification</p>
    </div>

    <div style="background-color: #fff7ed; border: 1px solid #fed7aa; border-radius: 10px; padding: 14px 18px; margin-bottom: 20px;">
      <p style="margin: 0; color: #c2410c; font-size: 14px; font-weight: bold; text-align: center;">
        PARTIAL DELIVERY RECEIVED — ACTIVE BACK-ORDER ($backorderId)
      </p>
    </div>

    <p style="color: #334155; font-size: 14px; line-height: 1.5;">
      Dear <strong>$greetingName</strong>,
    </p>
    <p style="color: #334155; font-size: 14px; line-height: 1.5;">
      This notification summarizes verified received items and remaining back-ordered items for Purchase Order <strong>#${_escapeHtml(po.poNumber)}</strong>. The official Back-Order PDF (<strong>${_escapeHtml(pdfFileName)}</strong>) is attached.
    </p>

    $supplierBlockHtml

    <table style="width: 100%; margin: 16px 0; font-size: 13px; color: #475569; border-collapse: collapse;">
      <tr>
        <td style="padding: 4px 0;"><strong>Original PO #:</strong> #${_escapeHtml(po.poNumber)}</td>
        <td style="padding: 4px 0; text-align: right;"><strong>Backorder ID:</strong> ${_escapeHtml(backorderId)}</td>
      </tr>
      <tr>
        <td style="padding: 4px 0;"><strong>Order Date:</strong> ${dateFormat.format(po.orderDate)}</td>
        <td style="padding: 4px 0; text-align: right;"><strong>Notice Date:</strong> ${dateFormat.format(DateTime.now())}</td>
      </tr>
      <tr>
        <td style="padding: 4px 0;"><strong>Status:</strong> ${_escapeHtml(po.status.displayName)}</td>
        <td style="padding: 4px 0; text-align: right;"><strong>Store Copy:</strong> ${_escapeHtml(storeEmail)}</td>
      </tr>
    </table>

    <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 16px 0;" />

    ${confirmedRowsHtml.isNotEmpty ? '''
    <h4 style="color: #047857; margin: 16px 0 12px 0; font-size: 14px;">CONFIRMED &amp; ACCEPTED ITEMS:</h4>
    <table style="width: 100%; border-collapse: collapse; margin-bottom: 20px;">
      <thead>
        <tr style="border-bottom: 2px solid #e2e8f0; text-align: left; color: #64748b; font-size: 11px; text-transform: uppercase;">
          <th style="padding: 6px 0; width: 55%;">Item Description</th>
          <th style="padding: 6px 0; width: 20%; text-align: center;">Confirmed Qty</th>
          <th style="padding: 6px 0; width: 25%; text-align: right;">Total Accepted</th>
        </tr>
      </thead>
      <tbody>
        $confirmedRowsHtml
      </tbody>
    </table>
    ''' : ''}

    ${backorderedRowsHtml.isNotEmpty ? '''
    <h4 style="color: #c2410c; margin: 16px 0 12px 0; font-size: 14px;">BACKORDERED ITEMS (UNFULFILLED):</h4>
    <table style="width: 100%; border-collapse: collapse; margin-bottom: 20px;">
      <thead>
        <tr style="border-bottom: 2px solid #ffedd5; text-align: left; color: #9a3412; font-size: 11px; text-transform: uppercase;">
          <th style="padding: 6px 0; width: 45%;">Item Description</th>
          <th style="padding: 6px 0; width: 30%; text-align: center;">Status</th>
          <th style="padding: 6px 0; width: 25%; text-align: right;">Backordered Qty</th>
        </tr>
      </thead>
      <tbody>
        $backorderedRowsHtml
      </tbody>
    </table>
    ''' : ''}

    <div style="background-color: #fefce8; border: 1px solid #fef08a; border-radius: 10px; padding: 16px; margin-top: 20px;">
      <h4 style="color: #854d0e; margin: 0 0 6px 0; font-size: 13.5px; font-weight: bold;">DELIVERY UPDATE &amp; THREADING NOTICE:</h4>
      <p style="color: #713f12; margin: 0; font-size: 13px; line-height: 1.5;">
        Kindly confirm the expected delivery schedule for the remaining back-ordered units above. Replies to this email route directly to ${_escapeHtml(storeEmail)}.
      </p>
    </div>

    <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 28px 0 20px 0;" />
    <p style="color: #94a3b8; font-size: 12px; text-align: center; margin: 0;">
      GDC Sari-Sari Store Management System
    </p>
  </div>
</div>
''';
    } else if (noticeType == NoticeType.fullDelivery) {
      auditAction = 'DELIVERY_CONFIRMATION_EMAIL';
      subject =
          '[GDC SARI-SARI STORE] Delivery Confirmation Successful - PO #${po.poNumber}';

      final StringBuffer receivedRowsHtml = StringBuffer();
      for (final item in po.items) {
        if (item.receivedQty > 0) {
          final double acceptedTotal =
              item.receivedQty * item.effectiveUnitCost;
          receivedRowsHtml.write('''
<tr style="border-bottom: 1px solid #f1f5f9;">
  <td style="padding: 8px 0; color: #1e293b; font-size: 13px;"><strong>${_escapeHtml(item.productName)}</strong> (SKU: ${_escapeHtml(item.sku.isNotEmpty ? item.sku : "N/A")})</td>
  <td style="padding: 8px 0; color: #047857; font-size: 13px; font-weight: bold; text-align: center;">${item.receivedQty}</td>
  <td style="padding: 8px 0; color: #0f172a; font-size: 13px; text-align: right;">${currencyFormat.format(acceptedTotal)}</td>
</tr>
''');
        }
      }

      final drDisplay =
          (deliveryReceiptNo != null && deliveryReceiptNo.trim().isNotEmpty)
              ? 'DR #${_escapeHtml(deliveryReceiptNo.trim())}'
              : 'Verified';

      htmlContent = '''
<div style="font-family: Arial, sans-serif; padding: 24px; background-color: #f8fafc;">
  <div style="max-width: 620px; margin: 0 auto; background-color: #ffffff; border-radius: 16px; padding: 36px; border: 1px solid #e2e8f0; box-shadow: 0 4px 12px rgba(0,0,0,0.05);">
    <div style="text-align: center; margin-bottom: 24px;">
      <h2 style="color: #047857; margin: 0; font-size: 22px; font-weight: bold; letter-spacing: 1px;">GDC SARI-SARI STORE</h2>
      <p style="color: #64748b; font-size: 13px; margin: 4px 0 0 0;">Official Delivery Verification Notice</p>
    </div>

    <div style="background-color: #ecfdf5; border: 1px solid #a7f3d0; border-radius: 10px; padding: 14px 18px; margin-bottom: 20px;">
      <p style="margin: 0; color: #047857; font-size: 14px; font-weight: bold; text-align: center;">
        DELIVERY FULFILLMENT SUCCESSFUL &amp; CONFIRMED
      </p>
    </div>

    <p style="color: #334155; font-size: 14px; line-height: 1.5;">
      Dear <strong>$greetingName</strong>,
    </p>
    <p style="color: #334155; font-size: 14px; line-height: 1.5;">
      We confirm that delivery receipt <strong>$drDisplay</strong> for Purchase Order <strong>#${_escapeHtml(po.poNumber)}</strong> has been fully received and verified.
    </p>

    $supplierBlockHtml

    <table style="width: 100%; margin: 16px 0; font-size: 13px; color: #475569;">
      <tr>
        <td style="padding: 4px 0;"><strong>PO Reference:</strong> #${_escapeHtml(po.poNumber)}</td>
        <td style="padding: 4px 0; text-align: right;"><strong>Delivery Receipt:</strong> $drDisplay</td>
      </tr>
      <tr>
        <td style="padding: 4px 0;"><strong>Order Date:</strong> ${dateFormat.format(po.orderDate)}</td>
        <td style="padding: 4px 0; text-align: right;"><strong>Updated Payable:</strong> ${currencyFormat.format(po.totalReceivedValue)}</td>
      </tr>
    </table>

    <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 16px 0;" />

    <h4 style="color: #047857; margin: 0 0 12px 0; font-size: 14px;">ITEMS RECEIVED &amp; ACCEPTED:</h4>
    <table style="width: 100%; border-collapse: collapse; margin-bottom: 20px;">
      <thead>
        <tr style="border-bottom: 2px solid #e2e8f0; text-align: left; color: #64748b; font-size: 11px; text-transform: uppercase;">
          <th style="padding: 6px 0; width: 60%;">Item</th>
          <th style="padding: 6px 0; width: 20%; text-align: center;">Accepted Qty</th>
          <th style="padding: 6px 0; width: 20%; text-align: right;">Accepted Cost</th>
        </tr>
      </thead>
      <tbody>
        $receivedRowsHtml
      </tbody>
    </table>

    <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 28px 0 20px 0;" />
    <p style="color: #94a3b8; font-size: 12px; text-align: center; margin: 0;">
      GDC Sari-Sari Store Management System
    </p>
  </div>
</div>
''';
    } else {
      auditAction = 'CANCEL_ORDER_EMAIL';
      final reasonText =
          (cancellationReason != null && cancellationReason.trim().isNotEmpty)
              ? cancellationReason.trim()
              : (po.cancelledReason ?? 'Remaining order closed short');
      subject =
          '[GDC SARI-SARI STORE] Order Cancellation / Close Short Notice - PO #${po.poNumber}';

      final StringBuffer cancelledRowsHtml = StringBuffer();
      for (final item in po.items) {
        if (item.remainingQty > 0) {
          cancelledRowsHtml.write('''
<tr style="border-bottom: 1px solid #fee2e2;">
  <td style="padding: 8px 0; color: #991b1b; font-size: 13px;"><strong>${_escapeHtml(item.productName)}</strong> (SKU: ${_escapeHtml(item.sku.isNotEmpty ? item.sku : "N/A")})</td>
  <td style="padding: 8px 0; color: #b91c1c; font-size: 13px; text-align: center;">Ordered: ${item.orderedQty} | Received: ${item.receivedQty}</td>
  <td style="padding: 8px 0; color: #dc2626; font-size: 13px; font-weight: bold; text-align: right;">Cancelled: ${item.remainingQty} units</td>
</tr>
''');
        }
      }

      htmlContent = '''
<div style="font-family: Arial, sans-serif; padding: 24px; background-color: #f8fafc;">
  <div style="max-width: 620px; margin: 0 auto; background-color: #ffffff; border-radius: 16px; padding: 36px; border: 1px solid #e2e8f0; box-shadow: 0 4px 12px rgba(0,0,0,0.05);">
    <div style="text-align: center; margin-bottom: 24px;">
      <h2 style="color: #dc2626; margin: 0; font-size: 22px; font-weight: bold; letter-spacing: 1px;">GDC SARI-SARI STORE</h2>
      <p style="color: #64748b; font-size: 13px; margin: 4px 0 0 0;">Official Order Cancellation / Close Short Notice</p>
    </div>

    <div style="background-color: #fef2f2; border: 1px solid #fecaca; border-radius: 10px; padding: 14px 18px; margin-bottom: 20px;">
      <p style="margin: 0; color: #991b1b; font-size: 14px; font-weight: bold; text-align: center;">
        REMAINING UNFULFILLED ORDER BALANCE CANCELLED
      </p>
    </div>

    <p style="color: #334155; font-size: 14px; line-height: 1.5;">
      Dear <strong>$greetingName</strong>,
    </p>
    <p style="color: #334155; font-size: 14px; line-height: 1.5;">
      This email serves as formal notification that the remaining unfulfilled balance for Purchase Order <strong>#${_escapeHtml(po.poNumber)}</strong> has been closed short / cancelled.
    </p>

    $supplierBlockHtml

    <div style="background-color: #f8fafc; border-left: 4px solid #dc2626; padding: 12px 16px; margin: 16px 0;">
      <p style="margin: 0; font-size: 13px; color: #475569;"><strong>Cancellation Reason:</strong> ${_escapeHtml(reasonText)}</p>
    </div>

    <table style="width: 100%; margin: 16px 0; font-size: 13px; color: #475569;">
      <tr>
        <td style="padding: 4px 0;"><strong>PO Reference:</strong> #${_escapeHtml(po.poNumber)}</td>
        <td style="padding: 4px 0; text-align: right;"><strong>Original Order Date:</strong> ${dateFormat.format(po.orderDate)}</td>
      </tr>
      <tr>
        <td style="padding: 4px 0;"><strong>Total Received Value:</strong> ${currencyFormat.format(po.totalReceivedValue)}</td>
        <td style="padding: 4px 0; text-align: right;"><strong>Status:</strong> CLOSED SHORT</td>
      </tr>
    </table>

    <h4 style="color: #991b1b; margin: 16px 0 12px 0; font-size: 14px;">CANCELLED ITEMS BREAKDOWN:</h4>
    <table style="width: 100%; border-collapse: collapse; margin-bottom: 20px;">
      <thead>
        <tr style="border-bottom: 2px solid #fecaca; text-align: left; color: #991b1b; font-size: 11px; text-transform: uppercase;">
          <th style="padding: 6px 0; width: 45%;">Item</th>
          <th style="padding: 6px 0; width: 30%; text-align: center;">Delivery History</th>
          <th style="padding: 6px 0; width: 25%; text-align: right;">Cancelled Qty</th>
        </tr>
      </thead>
      <tbody>
        $cancelledRowsHtml
      </tbody>
    </table>

    <p style="color: #64748b; font-size: 13px; line-height: 1.5;">
      Please adjust your billing records accordingly to reflect only physical accepted deliveries. The official cancellation notice PDF is attached.
    </p>

    <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 28px 0 20px 0;" />
    <p style="color: #94a3b8; font-size: 12px; text-align: center; margin: 0;">
      GDC Sari-Sari Store Management System
    </p>
  </div>
</div>
''';
    }

    final result = await _dispatchDualEmailWithPdf(
      snapshot: snapshot,
      subject: subject,
      htmlContent: htmlContent,
      pdfFileName: pdfFileName,
      pdfBytes: pdfBytes,
      storeEmailOverride: storeEmail,
    );

    await _recordDispatchAudit(
      po: po,
      snapshot: snapshot,
      noticeTypeKey: noticeType.name,
      auditAction: auditAction,
      summaryPrefix: '${noticeType.title} (PO #${po.poNumber}) dual-dispatch',
      result: result,
    );

    onStageChanged?.call(
      result.isFullSuccess ? DispatchStage.completed : DispatchStage.failed,
    );
    return result;
  }

  /// Legacy wrapper preserved for backwards compatibility; routes through [dispatchSupplierNoticeWithPdf].
  Future<bool> sendSupplierNoticeNotification({
    required BuildContext context,
    required PurchaseOrder po,
    Supplier? supplier,
    SupplierSnapshot? supplierSnapshot,
    required NoticeType noticeType,
    String? cancellationReason,
    List<ReceivingItem>? itemsReceived,
    required String actorEmail,
  }) async {
    final result = await dispatchSupplierNoticeWithPdf(
      po: po,
      supplier: supplier,
      supplierSnapshot: supplierSnapshot,
      noticeType: noticeType,
      cancellationReason: cancellationReason,
      itemsReceived: itemsReceived,
      actorEmail: actorEmail,
    );

    if (!result.isFullSuccess &&
        result.pdfBytes != null &&
        result.pdfFileName != null &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.summaryMessage),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      if (!result.supplierEmailSent) {
        await Printing.sharePdf(
          bytes: result.pdfBytes!,
          filename: result.pdfFileName!,
        );
      }
    }

    return result.isFullSuccess;
  }

  /// Legacy wrapper preserved for backwards compatibility; routes through [dispatchPurchaseOrderWithPdf].
  Future<bool> sendPoSubmissionEmailWithPdf({
    required PurchaseOrder po,
    Supplier? supplier,
    SupplierSnapshot? supplierSnapshot,
  }) async {
    final result = await dispatchPurchaseOrderWithPdf(
      po: po,
      supplier: supplier,
      supplierSnapshot: supplierSnapshot,
    );
    return result.isFullSuccess;
  }

  /// Legacy wrapper preserved for backwards compatibility; routes through [dispatchSupplierNoticeWithPdf].
  Future<bool> sendDeliveryConfirmationEmailWithPdf({
    required PurchaseOrder po,
    Supplier? supplier,
    SupplierSnapshot? supplierSnapshot,
    required bool isComplete,
    required String deliveryReceiptNo,
  }) async {
    final result = await dispatchSupplierNoticeWithPdf(
      po: po,
      supplier: supplier,
      supplierSnapshot: supplierSnapshot,
      noticeType: isComplete ? NoticeType.fullDelivery : NoticeType.backorder,
      deliveryReceiptNo: deliveryReceiptNo,
    );
    return result.isFullSuccess;
  }

  /// Legacy wrapper preserved for backwards compatibility; routes through [dispatchSupplierNoticeWithPdf].
  Future<bool> sendOrderCancellationEmailWithPdf({
    required PurchaseOrder po,
    Supplier? supplier,
    SupplierSnapshot? supplierSnapshot,
    required String reason,
  }) async {
    final result = await dispatchSupplierNoticeWithPdf(
      po: po,
      supplier: supplier,
      supplierSnapshot: supplierSnapshot,
      noticeType: NoticeType.cancellation,
      cancellationReason: reason,
    );
    return result.isFullSuccess;
  }

  /// Sends the **Store-Closing Resupply Summary Email** to the GDC Sari-Sari
  /// Store email account summarizing every product/variant whose 100% physical
  /// stock reached 30% of its original stock on [log.dateKey].
  Future<bool> sendDailyResupplySummaryEmail({
    required DailyResupplyLog log,
  }) async {
    final storeEmail = (log.storeEmail.trim().isNotEmpty)
        ? log.storeEmail.trim()
        : await resolveStoreEmail();
    if (storeEmail.isEmpty) {
      debugPrint(
        '[AdminMessagingService] Store Gmail address missing; skipping Store-Closing Resupply Summary.',
      );
      return false;
    }

    final items = log.sortedItems;
    if (items.isEmpty) {
      debugPrint(
        '[AdminMessagingService] No 30%-low-stock items for ${log.dateKey}; skipping Store-Closing Resupply Summary.',
      );
      return false;
    }

    final int oosCount = items.where((i) => i.isOutOfStock).length;
    final int onlineOosCount = items.where((i) => i.onlineOutOfStock).length;
    final int totalResupplyUnits = log.totalSuggestedUnits;
    final generatedStr =
        DateFormat('MMM d, yyyy • h:mm a').format(DateTime.now());

    final StringBuffer rowsBuffer = StringBuffer();
    for (final item in items) {
      final safeName = _escapeHtml(item.displayName);
      final safeCategory = _escapeHtml(item.category);
      final safeUnit = _escapeHtml(item.unit);
      final hitTime = DateFormat('h:mm a').format(item.firstTriggeredAt);
      final int orig = item.effectiveOriginalStock;
      final String statusBadge = item.isOutOfStock
          ? '<span style="background-color:#fee2e2;color:#b91c1c;padding:2px 7px;border-radius:6px;font-size:11px;font-weight:700;">OUT OF STOCK</span>'
          : '<span style="background-color:#fef3c7;color:#b45309;padding:2px 7px;border-radius:6px;font-size:11px;font-weight:700;">≤ 30% LOW STOCK</span>';
      final String onlineTag = item.onlineOutOfStock
          ? '<div style="font-size:11px;color:#b91c1c;margin-top:2px;">Online: Out of Stock</div>'
          : '<div style="font-size:11px;color:#475569;margin-top:2px;">Online: ${item.onlineStock} $safeUnit</div>';

      rowsBuffer.write('''
<tr style="border-bottom: 1px solid #e2e8f0;">
  <td style="padding: 10px 8px; vertical-align: top;">
    <div style="font-size: 13px; font-weight: 700; color: #0f172a;">$safeName</div>
    <div style="font-size: 11px; color: #64748b; margin-top: 2px;">$safeCategory • Reached 30% at $hitTime</div>
  </td>
  <td style="padding: 10px 8px; text-align: center; vertical-align: top;">
    <div style="font-size: 13px; font-weight: 700; color: ${item.isOutOfStock ? '#b91c1c' : '#b45309'};">${item.availableStock} / $orig $safeUnit</div>
    <div style="font-size: 11px; color: #64748b;">30% Alert: ≤ ${item.lowStockThreshold} $safeUnit</div>
  </td>
  <td style="padding: 10px 8px; text-align: center; vertical-align: top;">
    $statusBadge
    $onlineTag
  </td>
  <td style="padding: 10px 8px; text-align: right; vertical-align: top;">
    <div style="font-size: 14px; font-weight: 800; color: #0f766e;">+${item.suggestedResupplyQty} $safeUnit</div>
    <div style="font-size: 11px; color: #64748b;">Recommended</div>
  </td>
</tr>
''');
    }

    final htmlContent = '''
<div style="font-family: Arial, sans-serif; padding: 24px; background-color: #f8fafc;">
  <div style="max-width: 680px; margin: 0 auto; background-color: #ffffff; border-radius: 14px; padding: 28px; border: 1px solid #e2e8f0; box-shadow: 0 4px 12px rgba(0,0,0,0.05);">
    <div style="background: linear-gradient(135deg, #0f766e 0%, #115e59 100%); color: #ffffff; padding: 18px 20px; border-radius: 12px; margin-bottom: 22px;">
      <p style="margin: 0; font-size: 11px; letter-spacing: 0.9px; text-transform: uppercase; opacity: 0.9;">GDC Sari-Sari Store • Store-Closing Resupply Report</p>
      <h2 style="margin: 6px 0 0 0; font-size: 21px;">Store-Closing 30% Low-Stock Summary (${_escapeHtml(log.dateKey)})</h2>
      <p style="margin: 6px 0 0 0; font-size: 12px; opacity: 0.9;">Generated on store close • $generatedStr</p>
    </div>

    <p style="color: #334155; font-size: 14px; line-height: 1.6; margin-top: 0;">
      The store has closed for the day. Below is the complete summary of all products whose
      <strong>100% Physical Store stock reached 30% or less of their original stock</strong> today and require resupply.
      Walk-in POS retains access to the 25% physical-only reserve while online availability automatically closes once the 75% online cap is sold out.
    </p>

    <table style="width: 100%; border-collapse: separate; border-spacing: 8px 0; margin: 16px -8px;">
      <tr>
        <td style="background-color: #f0fdfa; border: 1px solid #99f6e4; border-radius: 10px; padding: 12px; text-align: center; width: 33%;">
          <div style="font-size: 22px; font-weight: 800; color: #0f766e;">${items.length}</div>
          <div style="font-size: 11px; color: #115e59; font-weight: 700; text-transform: uppercase;">Items at ≤ 30% Stock</div>
        </td>
        <td style="background-color: #fef2f2; border: 1px solid #fecaca; border-radius: 10px; padding: 12px; text-align: center; width: 33%;">
          <div style="font-size: 22px; font-weight: 800; color: #b91c1c;">$onlineOosCount</div>
          <div style="font-size: 11px; color: #991b1b; font-weight: 700; text-transform: uppercase;">Online Out of Stock ($oosCount Physical OOS)</div>
        </td>
        <td style="background-color: #eff6ff; border: 1px solid #bfdbfe; border-radius: 10px; padding: 12px; text-align: center; width: 33%;">
          <div style="font-size: 22px; font-weight: 800; color: #1d4ed8;">+$totalResupplyUnits</div>
          <div style="font-size: 11px; color: #1e40af; font-weight: 700; text-transform: uppercase;">Suggested Restock Units</div>
        </td>
      </tr>
    </table>

    <h3 style="color: #0f172a; font-size: 15px; margin: 22px 0 10px 0;">Products Requiring Resupply (≤ 30% Remaining)</h3>
    <table style="width: 100%; border-collapse: collapse; border: 1px solid #e2e8f0; border-radius: 8px;">
      <thead>
        <tr style="background-color: #f8fafc; border-bottom: 2px solid #e2e8f0; color: #475569; font-size: 11px; text-transform: uppercase;">
          <th style="padding: 10px 8px; text-align: left;">Product</th>
          <th style="padding: 10px 8px; text-align: center;">Physical / Original</th>
          <th style="padding: 10px 8px; text-align: center;">Stock Status</th>
          <th style="padding: 10px 8px; text-align: right;">Suggested Resupply</th>
        </tr>
      </thead>
      <tbody>
        $rowsBuffer
      </tbody>
    </table>

    <p style="color: #475569; font-size: 13px; line-height: 1.5; margin-top: 20px;">
      <strong>Next Steps:</strong> Review this store-closing resupply list and create a Purchase Order or log new FIFO stock deliveries in the GDC Admin App. Online availability will automatically reopen once new stock is received.
    </p>
    <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 20px 0;" />
    <p style="color: #94a3b8; font-size: 12px; margin: 0;">GDC Sari-Sari Store Inventory System • Store-Closing Resupply Summary</p>
  </div>
</div>
''';

    return await sendBrevoEmail(
      toEmail: storeEmail,
      recipientName: 'GDC Sari-Sari Store',
      subject:
          '📦 Store-Closing Resupply Summary (${log.dateKey}): ${items.length} item${items.length == 1 ? '' : 's'} reached 30% stock',
      htmlContent: htmlContent,
    );
  }
}
