import 'package:intl/intl.dart';

final _peso = NumberFormat.currency(locale: 'fil_PH', symbol: '₱');
String formatPeso(double amount) => _peso.format(amount);

String formatDate(DateTime dt) => DateFormat('MMM d, y hh:mm a').format(dt);

String formatTimeAgo(DateTime? dt) {
  if (dt == null) return 'Never';
  final diff = DateTime.now().difference(dt);
  if (diff.inDays > 0) return '${diff.inDays}d ago';
  if (diff.inHours > 0) return '${diff.inHours}h ago';
  if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
  return 'Just now';
}

/// Formats a phone number to E.164 format (e.g., +639123456789)
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

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
