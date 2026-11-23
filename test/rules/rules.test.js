const { describe, it, before, after, beforeEach } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, deleteDoc, Timestamp } = require('firebase/firestore');

const PROJECT_ID = 'demo-gdc-sari-sari';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

describe('GDC Sari-Sari Store Firestore Rules (Phase 3)', () => {
  it('allows customer to confirm payment on awaitingPayment order', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'orders', 'ord-1'), {
        orderId: 'ABC123',
        customerId: 'cust-1',
        customerEmail: 'cust1@example.com',
        status: 'awaitingPayment',
        paymentStatus: 'unpaid',
        isPaid: false,
        reservationReleased: false,
        total: 150,
      });
    });

    const custDb = testEnv.authenticatedContext('cust-1', { email: 'cust1@example.com' }).firestore();
    await assertSucceeds(
      updateDoc(doc(custDb, 'orders', 'ord-1'), {
        status: 'pending',
        paymentStatus: 'paid',
        isPaid: true,
        paymentReference: 'XEN-999',
        expiresAt: Timestamp.fromDate(new Date(Date.now() + 3600_000)),
      })
    );
  });

  it('allows customer to cancel own active order and set reservationReleased true once, blocks flipping back to false', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'orders', 'ord-2'), {
        orderId: 'DEF456',
        customerId: 'cust-1',
        status: 'pending',
        reservationReleased: false,
        total: 100,
      });
    });

    const custDb = testEnv.authenticatedContext('cust-1').firestore();
    await assertSucceeds(
      updateDoc(doc(custDb, 'orders', 'ord-2'), {
        status: 'cancelled',
        reservationReleased: true,
      })
    );

    await assertFails(
      updateDoc(doc(custDb, 'orders', 'ord-2'), {
        status: 'cancelled',
        reservationReleased: false,
      })
    );
  });

  it('blocks customer from marking an active order as collected', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'orders', 'ord-3'), {
        orderId: 'GHI789',
        customerId: 'cust-1',
        status: 'ready',
        reservationReleased: false,
      });
    });

    const custDb = testEnv.authenticatedContext('cust-1').firestore();
    await assertFails(
      updateDoc(doc(custDb, 'orders', 'ord-3'), { status: 'collected' })
    );
  });

  it('allows one-time pickup time extension and blocks a second extension', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'orders', 'ord-ext'), {
        orderId: 'EXT001',
        customerId: 'cust-1',
        status: 'ready',
        isExtended: false,
        extensionCount: 0,
        expiresAt: Timestamp.fromDate(new Date(Date.now() + 600_000)),
      });
    });

    const custDb = testEnv.authenticatedContext('cust-1').firestore();
    const newExpiry = Timestamp.fromDate(new Date(Date.now() + 1800_000));
    await assertSucceeds(
      updateDoc(doc(custDb, 'orders', 'ord-ext'), {
        expiresAt: newExpiry,
        pickupEnd: newExpiry,
        isExtended: true,
        extensionCount: 1,
      })
    );

    await assertFails(
      updateDoc(doc(custDb, 'orders', 'ord-ext'), {
        expiresAt: Timestamp.fromDate(new Date(Date.now() + 3600_000)),
        pickupEnd: Timestamp.fromDate(new Date(Date.now() + 3600_000)),
        isExtended: true,
        extensionCount: 2,
      })
    );
  });

  it('allows customer refund request (camelCase refundRequested), own refund cancel, and denies deleting or cancelling others', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const adminDb = ctx.firestore();
      await setDoc(doc(adminDb, 'orders', 'ord-ref'), {
        orderId: 'REF001',
        customerId: 'cust-ref-1',
        status: 'collected',
      });
      await setDoc(doc(adminDb, 'refund_requests', 'rr-1'), {
        transactionId: 'REF001',
        customerId: 'cust-ref-1',
        customerEmail: 'cust1@example.com',
        status: 'pending',
        total: 50,
      });
    });

    const cust1Db = testEnv.authenticatedContext('cust-ref-1').firestore();
    const cust2Db = testEnv.authenticatedContext('cust-ref-2').firestore();

    // Request refund on collected order with standardized camelCase
    await assertSucceeds(
      updateDoc(doc(cust1Db, 'orders', 'ord-ref'), { status: 'refundRequested' })
    );

    // Other user cannot cancel cust-ref-1's refund request
    await assertFails(
      updateDoc(doc(cust2Db, 'refund_requests', 'rr-1'), { status: 'cancelled' })
    );

    // Owner cannot DELETE refund request (must cancel via update)
    await assertFails(deleteDoc(doc(cust1Db, 'refund_requests', 'rr-1')));

    // Owner can cancel own pending refund request and revert order to collected
    await assertSucceeds(
      updateDoc(doc(cust1Db, 'refund_requests', 'rr-1'), { status: 'cancelled' })
    );
    await assertSucceeds(
      updateDoc(doc(cust1Db, 'orders', 'ord-ref'), { status: 'collected' })
    );
  });

  it('allows customer to update reservedStock on products but blocks physical stock or price tampering', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'products', 'prod-1'), {
        name: 'Pancit Canton',
        price: 15,
        costPrice: 11,
        stock: 10,
        reservedStock: 2,
      });
    });

    const custDb = testEnv.authenticatedContext('cust-1').firestore();

    // Reserve +2 (2 -> 4 <= 10) allowed
    await assertSucceeds(
      updateDoc(doc(custDb, 'products', 'prod-1'), { reservedStock: 4 })
    );
    // Release -2 (4 -> 2 >= 0) allowed
    await assertSucceeds(
      updateDoc(doc(custDb, 'products', 'prod-1'), { reservedStock: 2 })
    );
    // Physical stock mutation by customer denied
    await assertFails(
      updateDoc(doc(custDb, 'products', 'prod-1'), { stock: 5 })
    );
    // Price tampering denied
    await assertFails(
      updateDoc(doc(custDb, 'products', 'prod-1'), { price: 1 })
    );
  });

  it('blocks customer from tampering with offense fields including restrictionUntil', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', 'cust-1'), {
        email: 'cust1@example.com',
        role: 'customer',
        offenseCount: 2,
        restrictedUntil: Timestamp.fromDate(new Date(Date.now() + 86400_000)),
        restrictionUntil: Timestamp.fromDate(new Date(Date.now() + 86400_000)),
        isPermanentlyLocked: false,
      });
    });

    const custDb = testEnv.authenticatedContext('cust-1').firestore();

    await assertFails(
      updateDoc(doc(custDb, 'users', 'cust-1'), { restrictionUntil: null })
    );
    await assertFails(
      updateDoc(doc(custDb, 'users', 'cust-1'), { offenseCount: 0 })
    );

    // Restricted customer also cannot create a new order
    await assertFails(
      setDoc(doc(custDb, 'orders', 'ord-blocked'), {
        orderId: 'BLK001',
        customerId: 'cust-1',
        status: 'awaitingPayment',
        reservationReleased: false,
      })
    );
  });
});
