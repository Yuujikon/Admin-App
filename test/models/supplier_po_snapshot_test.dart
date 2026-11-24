import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdc_admin_app/models/purchase_order.dart';
import 'package:gdc_admin_app/models/supplier.dart';
import 'package:gdc_admin_app/shared/services/admin_messaging_service.dart';
import 'package:gdc_admin_app/utils/notice_pdf_printer.dart';
import 'package:gdc_admin_app/utils/po_pdf_printer.dart';

void main() {
  const validSupplier = Supplier(
    id: 'sup-001',
    name: 'Metro Manila Beverages Corp.',
    contactName: 'Maria Santos',
    phone: '+639171234567',
    email: 'orders@metrobeverages.ph',
    address: '123 Rizal Ave, Brgy. San Antonio, Pasig City',
    tin: '123-456-789-000',
    paymentTerms: 'Net 30',
    category: 'Beverages',
  );

  final sampleItems = [
    const PurchaseOrderItem(
      productId: 'prod-1',
      productName: 'Cola 1.5L Case (12s)',
      sku: '4800012345678',
      orderedQty: 20,
      receivedQty: 12,
      rejectedQty: 1,
      rejectionReason: 'Damaged seal',
      unitCost: 480.0,
      actualUnitCost: 485.0,
    ),
  ];

  group('SupplierSnapshot & Pre-Flight Validation Gate', () {
    test('validates complete supplier snapshot as ready for dispatch', () {
      final snapshot = validSupplier.toSnapshot();
      final result = snapshot.validateForDispatch();

      expect(result.isValid, isTrue);
      expect(result.blockingIssues, isEmpty);
      expect(result.advisoryIssues, isEmpty);
    });

    test('blocks when mandatory supplier fields are missing or malformed', () {
      const incomplete = SupplierSnapshot(
        supplierId: 'sup-002',
        supplierName: '',
        email: 'bad-email@mailinator.com',
        phone: '123',
        address: '',
      );

      final result = incomplete.validateForDispatch();

      expect(result.isValid, isFalse);
      expect(result.blockingIssues.length, equals(4));
      final keys = result.blockingIssues.map((e) => e.fieldKey).toSet();
      expect(keys, containsAll(['supplierName', 'email', 'phone', 'address']));
    });

    test('round-trips map serialization and merges fallback fields cleanly',
        () {
      final snapshot = validSupplier.toSnapshot(
        snapshottedAt: DateTime(2026, 11, 20),
      );
      final map = snapshot.toMap();
      final parsed = SupplierSnapshot.fromMap(map);

      expect(parsed.supplierId, equals('sup-001'));
      expect(parsed.supplierName, equals('Metro Manila Beverages Corp.'));
      expect(parsed.contactPerson, equals('Maria Santos'));
      expect(parsed.email, equals('orders@metrobeverages.ph'));
      expect(parsed.phone, equals('+639171234567'));
      expect(parsed.address,
          equals('123 Rizal Ave, Brgy. San Antonio, Pasig City'));
      expect(parsed.tin, equals('123-456-789-000'));
      expect(parsed.paymentTerms, equals('Net 30'));

      // Legacy partial snapshot fills missing address/tin from live supplier
      const partialSnapshot = SupplierSnapshot(
        supplierId: 'sup-001',
        supplierName: 'Custom Snapshot Name',
        email: 'orders@metrobeverages.ph',
      );
      final merged = partialSnapshot.mergeWithFallback(validSupplier);
      expect(merged.supplierName, equals('Custom Snapshot Name'));
      expect(merged.address, equals(validSupplier.address));
      expect(merged.phone, equals(validSupplier.phone));
    });
  });

  group('PO PDF & Backorder PDF Synchronization & Validation Gate', () {
    test('PO PDF and Backorder PDF reject incomplete supplier snapshots',
        () async {
      final invalidPo = PurchaseOrder(
        id: 'po-invalid',
        poNumber: 'PO-20261124-001',
        rfqId: '',
        supplierId: 'sup-bad',
        supplierName: 'Incomplete Vendor',
        supplierSnapshot: const SupplierSnapshot(
          supplierId: 'sup-bad',
          supplierName: 'Incomplete Vendor',
          email: '',
          phone: '',
          address: '',
        ),
        orderDate: DateTime(2026, 11, 24),
        items: sampleItems,
      );

      await expectLater(
        () => PoPdfPrinter.generatePoPdf(invalidPo, null),
        throwsA(isA<SupplierValidationException>()),
      );

      await expectLater(
        () => NoticePdfPrinter.generateSupplierNoticePdf(
          po: invalidPo,
          noticeType: NoticeType.backorder,
        ),
        throwsA(isA<SupplierValidationException>()),
      );
    });

    test(
        'PO PDF and Backorder/FullDelivery/Cancellation PDFs generate valid PDF bytes from snapshot',
        () async {
      final snapshot = validSupplier.toSnapshot();
      final validPo = PurchaseOrder(
        id: 'po-valid',
        poNumber: 'PO-20261124-101',
        rfqId: '',
        supplierId: validSupplier.id,
        supplierName: validSupplier.name,
        supplierSnapshot: snapshot,
        status: PurchaseOrderStatus.partiallyReceived,
        orderDate: DateTime(2026, 11, 24),
        requestedDeliveryDate: DateTime(2026, 11, 27),
        childPoId: 'BO-PO-20261124-101',
        items: sampleItems,
      );

      final poBytes = await PoPdfPrinter.generatePoPdf(validPo, null);
      expect(poBytes.length, greaterThan(500));
      expect(utf8.decode(poBytes.take(5).toList()), equals('%PDF-'));

      for (final type in NoticeType.values) {
        final noticeBytes = await NoticePdfPrinter.generateSupplierNoticePdf(
          po: validPo,
          noticeType: type,
          cancellationReason:
              type == NoticeType.cancellation ? 'Out of stock' : null,
        );
        expect(noticeBytes.length, greaterThan(500));
        expect(utf8.decode(noticeBytes.take(5).toList()), equals('%PDF-'));
      }
    });
  });

  group('Email HTML Supplier Section Parity', () {
    test('embeds all validated supplier metadata and escapes HTML safely', () {
      final snapshot = validSupplier.toSnapshot().copyWith(
            supplierName: 'R & D Trading <PH>',
          );
      final html =
          AdminMessagingService.buildValidatedSupplierHtmlSection(snapshot);

      expect(html, contains('R &amp; D Trading &lt;PH&gt;'));
      expect(html, contains('Maria Santos'));
      expect(html, contains('orders@metrobeverages.ph'));
      expect(html, contains('+639171234567'));
      expect(html, contains('123 Rizal Ave, Brgy. San Antonio, Pasig City'));
      expect(html, contains('123-456-789-000'));
      expect(html, contains('Net 30'));
      expect(html, isNot(contains('null')));
    });
  });
}
