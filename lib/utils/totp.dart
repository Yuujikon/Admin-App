import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class TotpUtils {
  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Encodes raw bytes into a Base32 string.
  static String base32Encode(List<int> bytes) {
    final buffer = StringBuffer();
    int value = 0;
    int bits = 0;

    for (int byte in bytes) {
      value = (value << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        buffer.write(_alphabet[(value >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    if (bits > 0) {
      buffer.write(_alphabet[(value << (5 - bits)) & 31]);
    }
    return buffer.toString();
  }

  /// Decodes a Base32 string into raw bytes.
  static List<int> base32Decode(String input) {
    final clean = input.toUpperCase().replaceAll('=', '').replaceAll(' ', '').replaceAll('-', '');
    final List<int> bytes = [];
    int buffer = 0;
    int bitsLeft = 0;

    for (int i = 0; i < clean.length; i++) {
      final char = clean[i];
      final val = _alphabet.indexOf(char);
      if (val < 0) continue;

      buffer = (buffer << 5) | val;
      bitsLeft += 5;

      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        bytes.add((buffer >> bitsLeft) & 0xFF);
      }
    }
    return bytes;
  }

  /// Generates a secure random 16-character Base32 secret key.
  static String generateSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(10, (_) => random.nextInt(256));
    return base32Encode(bytes);
  }

  /// Calculates a 6-digit TOTP code for a secret at the specified 30-second time interval.
  static String generateTotpCode(String base32Secret, {int? timeIntervalSeconds}) {
    final time = timeIntervalSeconds ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ 30);
    final secretBytes = base32Decode(base32Secret);

    if (secretBytes.isEmpty) return '000000';

    final timeBytes = Uint8List(8);
    var t = time;
    for (int i = 7; i >= 0; i--) {
      timeBytes[i] = t & 0xff;
      t >>= 8;
    }

    final hmac = Hmac(sha1, secretBytes);
    final digest = hmac.convert(timeBytes).bytes;

    final offset = digest[digest.length - 1] & 0x0f;
    final binary = ((digest[offset] & 0x7f) << 24) |
                   ((digest[offset + 1] & 0xff) << 16) |
                   ((digest[offset + 2] & 0xff) << 8) |
                   (digest[offset + 3] & 0xff);

    final otp = binary % 1000000;
    return otp.toString().padLeft(6, '0');
  }

  /// Verifies a 6-digit TOTP code with time drift tolerance (±1 interval / ±30s).
  static bool verifyTotpCode(String base32Secret, String inputCode) {
    final cleanInput = inputCode.trim();
    if (cleanInput.length != 6) return false;

    final currentInterval = DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ 30;

    for (int delta in [-1, 0, 1]) {
      final code = generateTotpCode(base32Secret, timeIntervalSeconds: currentInterval + delta);
      if (code == cleanInput) {
        return true;
      }
    }
    return false;
  }

  /// Formats secret key into readable groups of 4 (e.g., "ABCD EFGH IJKL MNOP").
  static String formatSecretReadable(String secret) {
    final clean = secret.replaceAll(' ', '');
    final chunks = <String>[];
    for (int i = 0; i < clean.length; i += 4) {
      final end = (i + 4 < clean.length) ? i + 4 : clean.length;
      chunks.add(clean.substring(i, end));
    }
    return chunks.join(' ');
  }
}
