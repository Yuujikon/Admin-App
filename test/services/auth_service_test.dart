import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gdc_admin_app/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService PIN Lockout Tests', () {
    late AuthService authService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      authService = AuthService();
    });

    test('initial state has no failed attempts and is not locked out', () async {
      final isLocked = await authService.isLockedOut();
      final failed = await authService.getFailedAttempts();
      final remSec = await authService.getRemainingLockoutSeconds();

      expect(isLocked, isFalse);
      expect(failed, equals(0));
      expect(remSec, equals(0));
    });

    test('verifies correct default PIN "1234"', () async {
      final isValid = await authService.verifyPin('1234');
      expect(isValid, isTrue);
    });

    test('records failed attempt and returns remaining attempts', () async {
      final res = await authService.recordFailedAttempt();

      expect(res['failedAttempts'], equals(1));
      expect(res['isLockedOut'], isFalse);
      expect(res['remainingAttempts'], equals(4));
    });

    test('locks out after 5 failed attempts', () async {
      for (int i = 0; i < 4; i++) {
        final res = await authService.recordFailedAttempt();
        expect(res['isLockedOut'], isFalse);
      }

      final fifthRes = await authService.recordFailedAttempt();
      expect(fifthRes['failedAttempts'], equals(5));
      expect(fifthRes['isLockedOut'], isTrue);
      expect(fifthRes['remainingSeconds'], greaterThan(0));

      final isLocked = await authService.isLockedOut();
      expect(isLocked, isTrue);

      final verifyResult = await authService.verifyPin('1234');
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
}
