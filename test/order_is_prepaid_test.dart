import 'package:flutter_test/flutter_test.dart';
import 'package:gdc_admin_app/models/order.dart';

void main() {
  PreOrder makeOrder({
    String paymentMethod = 'cash',
    String paymentStatus = 'unpaid',
    bool isPaid = false,
  }) {
    return PreOrder(
      id: 'ord-1',
      orderId: 'A1B2C3',
      customerName: 'Juan Dela Cruz',
      customerEmail: 'juan@example.com',
      items: const [],
      total: 100.0,
      status: OrderStatus.pending,
      createdAt: DateTime(2026, 11, 23, 10, 0),
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      isPaid: isPaid,
    );
  }

  group('PreOrder.isPrePaid', () {
    test('returns false for unpaid GCash or Maya orders', () {
      expect(
        makeOrder(paymentMethod: 'GCash', paymentStatus: 'unpaid', isPaid: false)
            .isPrePaid,
        isFalse,
      );
      expect(
        makeOrder(paymentMethod: 'Maya', paymentStatus: 'pending', isPaid: false)
            .isPrePaid,
        isFalse,
      );
    });

    test('returns true for paid GCash or Maya orders', () {
      expect(
        makeOrder(paymentMethod: 'GCash', paymentStatus: 'paid', isPaid: true)
            .isPrePaid,
        isTrue,
      );
      expect(
        makeOrder(paymentMethod: 'Maya', paymentStatus: 'completed', isPaid: false)
            .isPrePaid,
        isTrue,
      );
      expect(
        makeOrder(paymentMethod: 'GCash', paymentStatus: 'unpaid', isPaid: true)
            .isPrePaid,
        isTrue,
      );
    });

    test('returns false for cash orders regardless of paid flag', () {
      expect(
        makeOrder(paymentMethod: 'cash', paymentStatus: 'paid', isPaid: true)
            .isPrePaid,
        isFalse,
      );
      expect(
        makeOrder(
                paymentMethod: 'cash_on_pickup',
                paymentStatus: 'paid',
                isPaid: true)
            .isPrePaid,
        isFalse,
      );
    });
  });
}
