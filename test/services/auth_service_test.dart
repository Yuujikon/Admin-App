import 'package:flutter_test/flutter_test.dart';
import 'package:gdc_admin_app/services/auth_service.dart';
import 'package:gdc_admin_app/utils/email_validator.dart';
import 'package:gdc_admin_app/utils/format.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService PIN Lockout Tests', () {
    late AuthService authService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      authService = AuthService();
    });

    test('initial state has no failed attempts and is not locked out',
        () async {
      final isLocked = await authService.isLockedOut();
      final failed = await authService.getFailedAttempts();
      final remSec = await authService.getRemainingLockoutSeconds();

      expect(isLocked, isFalse);
      expect(failed, equals(0));
      expect(remSec, equals(0));
    });

    test('verifies correct default 6-digit PIN "123456"', () async {
      final isValid = await authService.verifyPin('123456');
      expect(isValid, isTrue);

      final isWrong = await authService.verifyPin('000000');
      expect(isWrong, isFalse);
    });

    test('records failed attempt and returns remaining attempts', () async {
      final res = await authService.recordFailedAttempt();

      expect(res['failedAttempts'], equals(1));
      expect(res['isLockedOut'], isFalse);
      expect(res['remainingAttempts'], equals(4));
    });

    test('locks out after 5 failed attempts and persists count', () async {
      for (int i = 0; i < 4; i++) {
        final res = await authService.recordFailedAttempt();
        expect(res['isLockedOut'], isFalse);
      }

      final fifthRes = await authService.recordFailedAttempt();
      expect(fifthRes['failedAttempts'], equals(5));
      expect(fifthRes['isLockedOut'], isTrue);
      expect(fifthRes['remainingSeconds'], greaterThan(0));

      expect(await authService.getFailedAttempts(), equals(5));
      expect(await authService.isLockedOut(), isTrue);

      final verifyResult = await authService.verifyPin('123456');
      expect(verifyResult, isFalse);
    });

    test('resets failed attempts on successful reset call', () async {
      await authService.recordFailedAttempt();
      await authService.recordFailedAttempt();

      await authService.resetFailedAttempts();

      final failed = await authService.getFailedAttempts();
      final isLocked = await authService.isLockedOut();

      expect(failed, equals(0));
      expect(isLocked, isFalse);
    });
  });

  group('Phone & Email Validation Tests', () {
    test('accepts valid Philippine and international phone numbers', () {
      expect(validatePhoneNumber('09123456789'), isNull);
      expect(validatePhoneNumber('+639123456789'), isNull);
      expect(validatePhoneNumber('639123456789'), isNull);
      expect(validatePhoneNumber('9123456789'), isNull);
      expect(validatePhoneNumber('0912-345-6789'), isNull);
    });

    test('rejects invalid phone numbers', () {
      expect(validatePhoneNumber(''), isNotNull);
      expect(validatePhoneNumber('abc123'), isNotNull);
      expect(validatePhoneNumber('09123'), isNotNull);
      expect(validatePhoneNumber('+63912345'), isNotNull);
    });

    test('formats Philippine numbers to E.164', () {
      expect(formatPhoneNumber('09123456789'), equals('+639123456789'));
      expect(formatPhoneNumber('9123456789'), equals('+639123456789'));
      expect(formatPhoneNumber('+639123456789'), equals('+639123456789'));
    });

    test('validates real vs disposable emails', () {
      expect(EmailValidator.validate('staff@gmail.com'), isNull);
      expect(EmailValidator.validate('invalid-email'), isNotNull);
      expect(EmailValidator.validate('fake@mailinator.com'), isNotNull);
    });
  });
}
