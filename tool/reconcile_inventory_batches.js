#!/usr/bin/env node
/**
 * Inventory Batch, Supplier Linkage & Stock Reconciliation Audit Script
 *
 * Audits and optionally repairs Firestore data across:
 *   - `suppliers/{supplierId}`
 *   - `purchase_orders/{poId}`
 *   - `products/{productId}` and `products/{productId}/batches/{batchId}`
 *   - `inventory_batches/{batchId}`
 *
 * Usage (dry-run by default — no writes):
 *   node tool/reconcile_inventory_batches.js
 *
 * Apply atomic fixes:
 *   node tool/reconcile_inventory_batches.js --apply
 *
 * Apply with fallback supplier for batches that have no PO or product supplier:
 *   node tool/reconcile_inventory_batches.js --apply --fallback-supplier=<SUPPLIER_DOC_ID>
 *
 * Optional project override:
 *   node tool/reconcile_inventory_batches.js --project=gdc-sari-sari-store-d5f06
 *
 * Prerequisites:
 *   - Run `npm install` inside `functions/` (so `firebase-admin` is available)
 *   - Authenticate with Application Default Credentials (`gcloud auth application-default login`)
 *     or set `GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json`.
 */

'use strict';

const path = require('path');

let admin;
try {
  admin = require('firebase-admin');
} catch (_) {
  admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));
}

const args = process.argv.slice(2);
const applyChanges = args.includes('--apply');
const dryRun = !applyChanges;

function getFlagValue(prefix) {
  const match = args.find((a) => a.startsWith(prefix));
  return match ? match.slice(prefix.length).trim() : null;
}

const projectId =
  getFlagValue('--project=') ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  process.env.GCLOUD_PROJECT ||
  'gdc-sari-sari-store-d5f06';

const fallbackSupplierId = getFlagValue('--fallback-supplier=');

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}

const db = admin.firestore();
const { FieldValue, Timestamp } = admin.firestore;

function toDate(val, fallback) {
  if (!val) return fallback;
  if (typeof val.toDate === 'function') return val.toDate();
  const parsed = new Date(val);
  return Number.isNaN(parsed.getTime()) ? fallback : parsed;
}

function normalizeBatch(docId, data, productId, productName, now = new Date()) {
  const remainingQty = Math.max(
    0,
    Math.trunc(
      Number(
        data.remainingQty ??
          data.quantityRemaining ??
          data.quantity ??
          0
      )
    )
  );
  const rawInitial = Math.trunc(
    Number(data.initialQty ?? data.initial_qty ?? remainingQty)
  );
  const initialQty = Math.max(rawInitial, remainingQty);
  const rawStatus = (data.status || '').toString().trim().toUpperCase();
  const dateArrived = toDate(
    data.dateArrived ?? data.dateReceived ?? data.createdAt,
    new Date(0)
  );
  const datePurchased = toDate(data.datePurchased, dateArrived);
  const expiryDate = data.expiryDate
    ? toDate(data.expiryDate, null)
    : data.expirationDate
      ? toDate(data.expirationDate, null)
      : null;
  const isExpired = expiryDate !== null && expiryDate.getTime() <= now.getTime();

  let status = 'ACTIVE';
  if (rawStatus === 'ARCHIVED') {
    status = 'ARCHIVED';
  } else if (remainingQty <= 0 || rawStatus === 'DEPLETED') {
    status = 'DEPLETED';
  } else if (isExpired || rawStatus === 'EXPIRED') {
    status = 'EXPIRED';
  }

  return {
    batchId: (data.batchId || docId).toString().trim() || docId,
    productId: (data.productId || productId).toString(),
    productName: (data.productName || productName || '').toString(),
    supplierId: data.supplierId ? data.supplierId.toString().trim() : null,
    supplierName: data.supplierName ? data.supplierName.toString().trim() : null,
    poId: data.poId ? data.poId.toString().trim() : null,
    poNumber: data.poNumber ? data.poNumber.toString().trim() : null,
    invoiceNumber: data.invoiceNumber ? data.invoiceNumber.toString().trim() : null,
    costPrice: Number(data.costPrice ?? data.unitCost ?? 0),
    initialQty,
    remainingQty,
    status,
    rawStatus,
    datePurchased,
    dateArrived,
    expiryDate,
  };
}

function isSellableBatch(b, now = new Date()) {
  return (
    b.status === 'ACTIVE' &&
    b.remainingQty > 0 &&
    (b.expiryDate === null || b.expiryDate.getTime() > now.getTime())
  );
}

function compareFifo(a, b) {
  if (a.expiryDate && b.expiryDate) {
    const expCmp = a.expiryDate.getTime() - b.expiryDate.getTime();
    if (expCmp !== 0) return expCmp;
  } else if (a.expiryDate && !b.expiryDate) {
    return -1;
  } else if (!a.expiryDate && b.expiryDate) {
    return 1;
  }
  const cmp = a.dateArrived.getTime() - b.dateArrived.getTime();
  if (cmp !== 0) return cmp;
  return a.batchId.localeCompare(b.batchId);
}

function batchToFirestore(b) {
  return {
    batchId: b.batchId,
    id: b.batchId,
    productId: b.productId,
    productName: b.productName,
    supplierId: b.supplierId,
    supplierName: b.supplierName,
    poId: b.poId,
    poNumber: b.poNumber,
    invoiceNumber: b.invoiceNumber,
    datePurchased: Timestamp.fromDate(b.datePurchased),
    dateArrived: Timestamp.fromDate(b.dateArrived),
    dateReceived: Timestamp.fromDate(b.dateArrived),
    createdAt: Timestamp.fromDate(b.dateArrived),
    expiryDate: b.expiryDate ? Timestamp.fromDate(b.expiryDate) : null,
    costPrice: b.costPrice,
    unitCost: b.costPrice,
    initialQty: b.initialQty,
    remainingQty: b.remainingQty,
    quantity: b.remainingQty,
    status: b.status,
  };
}

function batchToInventoryMirror(b) {
  return {
    batchId: b.batchId,
    productId: b.productId,
    productName: b.productName,
    supplierId: b.supplierId,
    supplierName: b.supplierName,
    poId: b.poId,
    poNumber: b.poNumber,
    initialQty: b.initialQty,
    quantityRemaining: b.remainingQty,
    remainingQty: b.remainingQty,
    unitCost: b.costPrice,
    costPrice: b.costPrice,
    datePurchased: Timestamp.fromDate(b.datePurchased),
    dateArrived: Timestamp.fromDate(b.dateArrived),
    receivedAt: Timestamp.fromDate(b.dateArrived),
    expiryDate: b.expiryDate ? Timestamp.fromDate(b.expiryDate) : null,
    status: b.status,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function main() {
  console.log('==============================================================');
  console.log(' Inventory Reconciliation & Orphan Supplier Audit');
  console.log(` Project : ${projectId}`);
  console.log(` Mode    : ${dryRun ? 'DRY-RUN (read-only)' : 'APPLY (atomic transactions)'}`);
  if (fallbackSupplierId) {
    console.log(` Fallback: ${fallbackSupplierId}`);
  }
  console.log('==============================================================\n');

  // 1. Load valid suppliers
  const suppliersSnap = await db.collection('suppliers').get();
  const suppliersById = new Map();
  for (const doc of suppliersSnap.docs) {
    const name = (doc.data().name || '').toString().trim();
    suppliersById.set(doc.id, name || 'Unnamed Supplier');
  }
  console.log(`Loaded ${suppliersById.size} supplier(s).`);

  if (fallbackSupplierId && !suppliersById.has(fallbackSupplierId)) {
    throw new Error(
      `Fallback supplier "${fallbackSupplierId}" does not exist in suppliers collection.`
    );
  }

  // 2. Load Purchase Orders for PO -> Supplier inference
  const posSnap = await db.collection('purchase_orders').get();
  const poSupplierByPoId = new Map();
  const poSupplierByPoNumber = new Map();
  for (const doc of posSnap.docs) {
    const data = doc.data();
    const sId = (data.supplierId || '').toString().trim();
    if (!sId || !suppliersById.has(sId)) continue;
    poSupplierByPoId.set(doc.id, sId);
    const poNum = (data.poNumber || '').toString().trim().toLowerCase();
    if (poNum) {
      poSupplierByPoNumber.set(poNum, sId);
    }
  }
  console.log(`Loaded ${posSnap.size} purchase order(s).\n`);

  // 2b. Compute authoritative reservedStock from open orders (pending/staging/ready)
  const openOrdersSnap = await db
    .collection('orders')
    .where('status', 'in', ['pending', 'staging', 'ready'])
    .get();
  const expectedReservedByProduct = new Map();
  for (const doc of openOrdersSnap.docs) {
    const oData = doc.data();
    if (oData.reservationReleased === true) continue;
    const items = Array.isArray(oData.items) ? oData.items : [];
    for (const item of items) {
      const pid = (item?.productId || '').toString().trim();
      const qty = Math.max(0, Math.trunc(Number(item?.qty ?? 0)));
      if (!pid || qty <= 0) continue;
      expectedReservedByProduct.set(
        pid,
        (expectedReservedByProduct.get(pid) || 0) + qty
      );
    }
  }
  console.log(`Loaded ${openOrdersSnap.size} open pickup order(s) for reservedStock audit.\n`);

  // 3. Scan products & subcollection batches
  const now = new Date();
  const productsSnap = await db.collection('products').get();

  let productsScanned = 0;
  let batchesScanned = 0;
  let batchesSupplierFixed = 0;
  let productsStockFixed = 0;

  const orphanFindings = [];
  const driftFindings = [];

  for (const prodDoc of productsSnap.docs) {
    const pData = prodDoc.data();
    const variants = Array.isArray(pData.variants) ? pData.variants : [];
    if (variants.length > 0) continue; // Variant products manage stock per variant

    productsScanned++;
    const productId = prodDoc.id;
    const productName = (pData.name || productId).toString();
    const storedStock = Math.trunc(Number(pData.stock ?? 0));
    const storedReserved = Math.trunc(Number(pData.reservedStock ?? 0));
    const expectedReserved = expectedReservedByProduct.get(productId) || 0;
    const productSupplierId = (pData.supplierId || '').toString().trim();
    const embeddedList = Array.isArray(pData.batches)
      ? pData.batches
      : pData.batches && typeof pData.batches === 'object'
        ? Object.values(pData.batches)
        : [];
    const embeddedSum = embeddedList.reduce((acc, b) => {
      const norm = normalizeBatch(b?.batchId || b?.id || '', b || {}, productId, productName, now);
      return isSellableBatch(norm, now) ? acc + norm.remainingQty : acc;
    }, 0);

    const subSnap = await prodDoc.ref.collection('batches').get();
    const batches = subSnap.docs
      .map((d) => normalizeBatch(d.id, d.data(), productId, productName, now))
      .sort(compareFifo);

    batchesScanned += batches.length;

    // 3a. Audit supplier linkage per batch
    const supplierFixesForProduct = new Map();

    for (const b of batches) {
      const hasValidSupplier = Boolean(b.supplierId && suppliersById.has(b.supplierId));
      const needsNameSync =
        hasValidSupplier &&
        (!b.supplierName || b.supplierName !== suppliersById.get(b.supplierId));

      if (hasValidSupplier && !needsNameSync) continue;

      let suggestedId = null;
      if (hasValidSupplier) {
        suggestedId = b.supplierId;
      } else if (b.poId && poSupplierByPoId.has(b.poId)) {
        suggestedId = poSupplierByPoId.get(b.poId);
      } else if (b.poNumber && poSupplierByPoNumber.has(b.poNumber.toLowerCase())) {
        suggestedId = poSupplierByPoNumber.get(b.poNumber.toLowerCase());
      } else if (productSupplierId && suppliersById.has(productSupplierId)) {
        suggestedId = productSupplierId;
      } else if (fallbackSupplierId) {
        suggestedId = fallbackSupplierId;
      }

      if (!hasValidSupplier) {
        orphanFindings.push({
          productId,
          productName,
          batchId: b.batchId,
          remainingQty: b.remainingQty,
          currentSupplierId: b.supplierId,
          reason: b.supplierId
            ? `Broken supplierId "${b.supplierId}"`
            : 'Missing supplierId',
          suggestedSupplierId: suggestedId,
          suggestedSupplierName: suggestedId ? suppliersById.get(suggestedId) : null,
        });
      }

      if (suggestedId) {
        supplierFixesForProduct.set(b.batchId, {
          supplierId: suggestedId,
          supplierName: suppliersById.get(suggestedId),
        });
      }
    }

    // 3b. Compare stored product.stock & reservedStock vs valid sellable subcollection sum
    const activeBatchSum = batches
      .filter((b) => isSellableBatch(b, now))
      .reduce((acc, b) => acc + b.remainingQty, 0);

    const statusChangesNeeded = batches.some((b) => b.rawStatus !== b.status);
    const hasStockDrift = storedStock !== activeBatchSum;
    const hasReservedDrift = storedReserved !== expectedReserved;
    const embeddedOutOfSync =
      embeddedSum !== activeBatchSum || embeddedList.length !== batches.length;

    if (hasStockDrift || hasReservedDrift || embeddedOutOfSync || statusChangesNeeded) {
      driftFindings.push({
        productId,
        productName,
        storedStock,
        activeBatchSum,
        storedReserved,
        expectedReserved,
        delta: activeBatchSum - storedStock,
        embeddedOutOfSync,
        statusChangesNeeded,
      });
    }

    // 3c. Apply fixes atomically inside a transaction per affected product
    if (
      !dryRun &&
      (hasStockDrift ||
        hasReservedDrift ||
        embeddedOutOfSync ||
        statusChangesNeeded ||
        supplierFixesForProduct.size > 0)
    ) {
      const txResult = await db.runTransaction(async (tx) => {
        const txNow = new Date();
        const freshProd = await tx.get(prodDoc.ref);
        if (!freshProd.exists) return { linked: 0, stockUpdated: false };

        const freshSub = await prodDoc.ref.collection('batches').get();
        const updatedBatches = [];
        let linked = 0;

        for (const doc of freshSub.docs) {
          const b = normalizeBatch(doc.id, doc.data(), productId, productName, txNow);
          const fix = supplierFixesForProduct.get(b.batchId);
          const next = fix
            ? { ...b, supplierId: fix.supplierId, supplierName: fix.supplierName }
            : b;

          if (fix || b.rawStatus !== b.status) {
            tx.set(
              doc.ref,
              {
                ...(fix
                  ? { supplierId: fix.supplierId, supplierName: fix.supplierName }
                  : {}),
                status: next.status,
                updatedAt: FieldValue.serverTimestamp(),
              },
              { merge: true }
            );
            if (fix) linked++;
          }

          tx.set(
            db.collection('inventory_batches').doc(next.batchId),
            batchToInventoryMirror(next),
            { merge: true }
          );
          updatedBatches.push(next);
        }

        updatedBatches.sort(compareFifo);
        const activeBatches = updatedBatches.filter((b) => isSellableBatch(b, txNow));
        const syncedStock = activeBatches.reduce((acc, b) => acc + b.remainingQty, 0);
        const earliestExp = activeBatches.find((b) => b.expiryDate !== null)?.expiryDate || null;

        const batchesMap = {};
        for (const b of updatedBatches) {
          batchesMap[b.batchId] = batchToFirestore(b);
        }

        const parentUpdate = {
          stock: syncedStock,
          reservedStock: expectedReserved,
          batches: batchesMap,
          expiryDate: earliestExp ? Timestamp.fromDate(earliestExp) : null,
          updatedAt: FieldValue.serverTimestamp(),
        };
        if (activeBatches.length > 0 && activeBatches[0].costPrice > 0) {
          parentUpdate.costPrice = activeBatches[0].costPrice;
        }
        tx.update(prodDoc.ref, parentUpdate);

        return {
          linked,
          stockUpdated: hasStockDrift || hasReservedDrift || embeddedOutOfSync || statusChangesNeeded,
        };
      });

      batchesSupplierFixed += txResult.linked;
      if (txResult.stockUpdated) productsStockFixed++;
    }
  }

  // 4. Print report
  console.log(`Scanned ${productsScanned} non-variant product(s) and ${batchesScanned} batch(es).\n`);

  console.log(`--- (A) Orphan / Unlinked Batches: ${orphanFindings.length} ---`);
  if (orphanFindings.length === 0) {
    console.log('  OK: Every batch has a valid supplierId.\n');
  } else {
    for (const f of orphanFindings) {
      const resolution = f.suggestedSupplierId
        ? `-> can link to ${f.suggestedSupplierName} (${f.suggestedSupplierId})`
        : '-> NO AUTO-MATCH (pass --fallback-supplier=<id> or link in UI)';
      console.log(
        `  [ORPHAN] ${f.productName} (${f.productId}) | Batch ${f.batchId} | qty=${f.remainingQty} | ${f.reason} ${resolution}`
      );
    }
    console.log('');
  }

  console.log(`--- (B) Out-of-Sync Product Stock Counts: ${driftFindings.length} ---`);
  if (driftFindings.length === 0) {
    console.log('  OK: All product stock counts and embedded mirrors match active batches.\n');
  } else {
    for (const d of driftFindings) {
      const sign = d.delta >= 0 ? '+' : '';
      const mirrorFlag = d.embeddedOutOfSync ? ' [embedded mirror stale]' : '';
      console.log(
        `  [DRIFT]  ${d.productName} (${d.productId}) | stored=${d.storedStock} -> activeBatches=${d.activeBatchSum} (${sign}${d.delta})${mirrorFlag}`
      );
    }
    console.log('');
  }

  if (dryRun) {
    if (orphanFindings.length > 0 || driftFindings.length > 0) {
      console.log('Dry-run complete. Re-run with --apply to repair atomically.');
    } else {
      console.log('Dry-run complete. No discrepancies detected.');
    }
  } else {
    console.log(
      `Applied fixes atomically: ${batchesSupplierFixed} batch supplier link(s) updated, ${productsStockFixed} product stock record(s) synchronized.`
    );
  }
}

main().catch((err) => {
  console.error('\nReconciliation script failed:', err);
  process.exitCode = 1;
});
