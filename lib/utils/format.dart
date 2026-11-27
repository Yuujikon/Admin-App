import 'package:intl/intl.dart';
import '../shared/services/time_service.dart';

final _peso = NumberFormat.currency(locale: 'fil_PH', symbol: 'P');

/// Formats a monetary amount into Philippine Peso currency representation.
String formatPeso(double amount) => _peso.format(amount);

/// Alias for [formatPeso] for unified currency formatting.
String formatCurrency(double amount) => formatPeso(amount);

/// Formats a [DateTime] into a localized string (`MMM d, y hh:mm a`).
String formatDate(DateTime dt) => DateFormat('MMM d, y hh:mm a').format(dt);

/// Formats a relative time ago string (e.g. "5m ago", "2h ago", "1d ago", or "Just now").
String formatTimeAgo(DateTime? dt) {
  if (dt == null) return 'Never';
  final diff = TimeService.now.difference(dt);
  if (diff.inDays > 0) return '${diff.inDays}d ago';
  if (diff.inHours > 0) return '${diff.inHours}h ago';
  if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
  return 'Just now';
}

/// Validates a phone number string (supports Philippine mobile formats such as
/// `09XXXXXXXXX`, `+639XXXXXXXXX`, `639XXXXXXXXX`, `9XXXXXXXXX`, as well as
/// standard 10–15 digit international numbers).
///
/// Returns `null` if valid, or a descriptive error message if invalid.
String? validatePhoneNumber(String? input) {
  if (input == null || input.trim().isEmpty) {
    return 'Please enter your contact phone number.';
  }

  final cleaned = input.trim().replaceAll(RegExp(r'[\s\-()]'), '');
  if (!RegExp(r'^\+?[0-9]+$').hasMatch(cleaned)) {
    return 'Phone number may only contain digits and an optional leading +.';
  }

  if (cleaned.startsWith('09')) {
    if (cleaned.length != 11) {
      return 'Philippine mobile numbers starting with 09 must be 11 digits (e.g. 09123456789).';
    }
    return null;
  }

  if (cleaned.startsWith('+639')) {
    if (cleaned.length != 13) {
      return 'Philippine mobile numbers starting with +639 must be 13 characters (e.g. +639123456789).';
    }
    return null;
  }

  if (cleaned.startsWith('639')) {
    if (cleaned.length != 12) {
      return 'Philippine mobile numbers starting with 639 must be 12 digits.';
    }
    return null;
  }

  if (cleaned.startsWith('9') && !cleaned.startsWith('+')) {
    if (cleaned.length != 10) {
      return 'Please enter a valid 11-digit mobile number (e.g. 09123456789).';
    }
    return null;
  }

  final digitsOnly = cleaned.replaceAll('+', '');
  if (digitsOnly.length < 10 || digitsOnly.length > 15) {
    return 'Please enter a valid phone number (10–15 digits).';
  }

  return null;
}

/// Formats a phone number string to E.164 international format (e.g., +639123456789).
String formatPhoneNumber(String phone) {
  // Remove all non-numeric characters except for the leading +
  String sanitized = phone.replaceAll(RegExp(r'[^0-9+]'), '');

  // If it starts with 0, assume it's a local Philippines number and replace with +63
  if (sanitized.startsWith('0')) {
    return '+63${sanitized.substring(1)}';
  }

  // If it starts with 9 (common in PH mobile numbers), add +63
  if (sanitized.startsWith('9') && sanitized.length == 10) {
    return '+63$sanitized';
  }

  // If it doesn't have a +, add it (assuming it's a full international number without +)
  if (sanitized.isNotEmpty && !sanitized.startsWith('+')) {
    return '+$sanitized';
  }

  return sanitized;
}

/// String extension for text capitalization.
extension StringExtension on String {
  /// Capitalizes the first character of string.
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
