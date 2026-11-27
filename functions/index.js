const {
  onDocumentUpdated,
  onDocumentCreated,
} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const {setGlobalOptions} = require("firebase-functions");

admin.initializeApp();
setGlobalOptions({maxInstances: 10});

/**
 * Triggered when an order status changes.
 * Sends a push notification to the customer.
 */
exports.onOrderStatusChange = onDocumentUpdated(
    "orders/{orderId}",
    async (event) => {
      const newValue = event.data.after.data();
      const previousValue = event.data.before.data();

      if (newValue.status === previousValue.status) return;

      const customerEmail = newValue.customerEmail;
      if (!customerEmail) return;

      const topicName = `customer_${customerEmail.replace(/[@.]/g, "_")}`;

      let title = "";
      let body = "";

      switch (newValue.status) {
        case "staging":
          title = "Order Being Packed 📦";
          body = `We've started packing your order ${newValue.orderId}!`;
          break;
        case "ready":
          title = "Order Ready! 🛍️";
          body = `Order ${newValue.orderId} is ready for pickup at GDC.`;
          break;
        case "cancelled":
          title = "Order Cancelled ⚠️";
          body = `Your order ${newValue.orderId} has been cancelled. ` +
            `${newValue.rejectionReason || ""}`;
          break;
        case "collected":
          title = "Thanks for Shopping! ❤️";
          body = `Order ${newValue.orderId} was collected. ` +
            "See you again soon!";
          break;
        default:
          return;
      }

      const message = {
        notification: {
          title: title,
          body: body,
        },
        data: {
          orderId: newValue.orderId,
          status: newValue.status,
          recipient: "customer",
        },
        topic: topicName,
      };

      try {
        await admin.messaging().send(message);
        console.log(`Notification sent to topic: ${topicName}`);
      } catch (error) {
        console.error("Error sending notification:", error);
      }
    },
);

/**
 * Kept for backwards compatibility with deployed triggers.
 */
exports.onRefundRequestCreated = onDocumentUpdated(
    "refund_requests/{requestId}",
    async () => {
      // Kept for backwards compatibility with deployed triggers.
    },
);

/**
 * Triggered when a new refund request is created.
 * Sends a push notification to the Admin.
 */
exports.onNewRefundRequest = onDocumentCreated(
    "refund_requests/{requestId}",
    async (event) => {
      const data = event.data.data();

      const message = {
        notification: {
          title: "New Refund Request 💸",
          body: `Customer ${data.customerName} requested a refund ` +
            `for sale #${data.transactionId}.`,
        },
        data: {
          recipient: "admin",
          type: "refund_request",
        },
        topic: "admin_alerts",
      };

      try {
        await admin.messaging().send(message);
        console.log("Admin notification sent for refund request.");
      } catch (error) {
        console.error("Error sending admin notification:", error);
      }
    },
);

const STORE_GMAIL_ADDRESS =
  process.env.STORE_GMAIL_EMAIL || "gdcstore.ph@gmail.com";

/**
 * Calculates the 25% physical-only reserve (rounded up so walk-in POS
 * stock is always protected on odd quantities).
 * @param {number} totalStock Total physical stock.
 * @return {number} Physical reserve units.
 */
function calculatePhysicalReserve(totalStock) {
  const safeTotal = Math.max(0, Math.floor(Number(totalStock) || 0));
  if (safeTotal <= 0) return 0;
  return Math.ceil(safeTotal * 0.25);
}

/**
 * Resolves the active physical reserve, falling back to 25% of total stock
 * for legacy product documents that predate `physicalReserve`.
 * @param {number} totalStock Total physical stock.
 * @param {*} storedReserve Optional stored `physicalReserve` field.
 * @return {number} Effective physical reserve units.
 */
function resolvePhysicalReserve(totalStock, storedReserve) {
  const safeTotal = Math.max(0, Math.floor(Number(totalStock) || 0));
  if (
    storedReserve !== undefined &&
    storedReserve !== null &&
    Number.isFinite(Number(storedReserve)) &&
    Number(storedReserve) >= 0
  ) {
    return Math.floor(Number(storedReserve));
  }
  return calculatePhysicalReserve(safeTotal);
}

/**
 * Dynamically computes Online Available Stock (`max(0, available - reserve)`).
 * Online orders can never dip into the 25% physical-only reserve.
 * @param {number} availableStock Unreserved physical stock.
 * @param {number} physicalReserve Walk-in physical reserve units.
 * @return {number} Online sellable units.
 */
function calculateOnlineAvailable(availableStock, physicalReserve) {
  const safeAvail = Math.max(0, Math.floor(Number(availableStock) || 0));
  const safeReserve = Math.max(0, Math.floor(Number(physicalReserve) || 0));
  return Math.max(0, safeAvail - safeReserve);
}

/**
 * Calculates the 30% low-stock alert threshold from the original physical
 * stock (rounded up so even small batches trigger at >= 1 unit).
 * @param {number} originalStock Baseline original physical stock.
 * @return {number} 30% low-stock trigger units.
 */
function calculateLowStockTrigger(originalStock) {
  const safeOriginal = Math.max(0, Math.floor(Number(originalStock) || 0));
  if (safeOriginal <= 0) return 0;
  return Math.ceil(safeOriginal * 0.30);
}

/**
 * Returns the mathematically exact minimum original stock `N` whose 25%
 * physical reserve equals `physicalReserve` (`ceil(N * 0.25) === R`).
 * @param {*} physicalReserve Stored physical reserve units.
 * @return {number} Minimum original stock lower bound.
 */
function minOriginalStockFromReserve(physicalReserve) {
  const safeReserve = Math.floor(Number(physicalReserve) || 0);
  if (safeReserve <= 0) return 0;
  return ((safeReserve - 1) * 4) + 1;
}

/**
 * Resolves the baseline original physical stock for 30% low-stock evaluation,
 * supporting legacy products without `initialStock` via FIFO batches, stored
 * `physicalReserve`, and prior stock snapshot.
 * @param {number} totalStock Current physical stock.
 * @param {*} storedInitialStock Optional stored `initialStock` field.
 * @param {Object} [opts] Optional fallback metadata.
 * @param {*} [opts.batches] Product batches map/array.
 * @param {*} [opts.physicalReserve] Stored `physicalReserve` field.
 * @param {number} [opts.previousStock] Stock before this update.
 * @return {number} Effective original stock.
 */
function resolveOriginalStock(totalStock, storedInitialStock, opts = {}) {
  const safeTotal = Math.max(0, Math.floor(Number(totalStock) || 0));
  const safeInitial = Math.max(0, Math.floor(Number(storedInitialStock) || 0));
  let baseline = Math.max(safeTotal, safeInitial);

  const rawBatches = opts.batches;
  const batchList = Array.isArray(rawBatches) ?
    rawBatches :
    (rawBatches && typeof rawBatches === "object" ?
      Object.values(rawBatches) :
      []);
  if (batchList.length > 0) {
    let activeInitSum = 0;
    let nonArchivedMaxInit = 0;
    for (const b of batchList) {
      if (!b || typeof b !== "object") continue;
      const status = String(b.status || "ACTIVE").trim().toUpperCase();
      const rawRem = b.remainingQty !== undefined && b.remainingQty !== null ?
        b.remainingQty :
        b.quantity;
      const rem = Math.max(0, Math.floor(Number(rawRem) || 0));
      const rawInit = b.initialQty !== undefined && b.initialQty !== null ?
        b.initialQty :
        rem;
      const init = Math.max(0, Math.floor(Number(rawInit) || 0));
      if (status !== "ARCHIVED" && init > nonArchivedMaxInit) {
        nonArchivedMaxInit = init;
      }
      if (status === "ACTIVE" && rem > 0) {
        activeInitSum += init;
      }
    }
    if (activeInitSum > baseline) baseline = activeInitSum;
    if (baseline <= 0 && nonArchivedMaxInit > 0) {
      baseline = nonArchivedMaxInit;
    }
  }

  if (safeInitial <= 0) {
    const fromReserve = minOriginalStockFromReserve(opts.physicalReserve);
    if (fromReserve > baseline) baseline = fromReserve;
    const prevStock = Math.max(0, Math.floor(Number(opts.previousStock) || 0));
    if (prevStock > baseline) baseline = prevStock;
  }

  return baseline;
}

/**
 * Computes suggested resupply quantity to restore stock back to its
 * original stock baseline.
 * @param {number} availableStock Current unreserved physical stock.
 * @param {number} originalStock Baseline original physical stock.
 * @return {number} Suggested resupply quantity.
 */
function calculateSuggestedRestock(availableStock, originalStock) {
  const safeAvail = Math.max(0, Math.floor(Number(availableStock) || 0));
  const safeOriginal = Math.max(0, Math.floor(Number(originalStock) || 0));
  const safeTrigger = Math.max(1, calculateLowStockTrigger(safeOriginal));
  const targetStock = Math.max(safeOriginal, safeTrigger * 2);
  return Math.max(1, targetStock - safeAvail);
}

/**
 * Converts a Firestore Timestamp, Date, or ISO string into a Date or null.
 * @param {*} raw Raw timestamp value.
 * @return {Date|null} Parsed Date instance or null.
 */
function toDateOrNull(raw) {
  if (!raw) return null;
  if (typeof raw.toDate === "function") return raw.toDate();
  if (raw instanceof Date) return raw;
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

/**
 * Determines whether the store has closed for the day at `nowDate`,
 * matching `StoreSettings.hasStoreClosedForDayAt`.
 * Does NOT fire early in the morning before opening on a regular open day.
 * @param {Object} settingsData Firestore `settings/store_settings` data.
 * @param {{year: number, month: number, day: number,
 *   hour: number, minute: number}} manilaNow Asia/Manila date/time parts.
 * @param {Date} nowDate Current UTC Date instance.
 * @return {boolean} True if store has closed for the day.
 */
function hasStoreClosedForDay(settingsData, manilaNow, nowDate) {
  const data = settingsData || {};
  if (data.isClosed === true) return true;

  const sClose = toDateOrNull(data.scheduledCloseAt);
  const sOpen = toDateOrNull(data.scheduledOpenAt);
  if (sClose && sOpen && nowDate > sClose && nowDate < sOpen) {
    return true;
  }

  const curMins = (manilaNow.hour * 60) + manilaNow.minute;
  const todayKey = formatDateKeyFromParts(manilaNow);
  const overrides = Array.isArray(data.overrides) ? data.overrides : [];
  const matchingOverrides = overrides.filter((o) => {
    if (!o) return false;
    const startDate = toDateOrNull(o.startDate);
    const endDate = toDateOrNull(o.endDate);
    if (!startDate || !endDate) return false;
    const startKey = getManilaDateKey(startDate);
    const endKey = getManilaDateKey(endDate);
    return todayKey >= startKey && todayKey <= endKey;
  });

  if (matchingOverrides.length > 0) {
    if (matchingOverrides.some((o) => o.type === "fullClosure")) {
      return true;
    }
    for (const o of matchingOverrides) {
      if (
        o.type === "customOpenHours" &&
        o.endMinutes !== undefined &&
        o.endMinutes !== null &&
        Number.isFinite(Number(o.endMinutes))
      ) {
        return curMins >= Number(o.endMinutes);
      }
    }
  }

  const closeTime = parseCloseTime(data.dailyCloseTime);
  const closeMins = (closeTime.hour * 60) + closeTime.minute;
  return curMins >= closeMins;
}

/**
 * Builds a sanitized Firestore document ID segment from an item key.
 * @param {string} raw Raw identifier.
 * @return {string} Safe document ID fragment.
 */
function sanitizeDocIdSegment(raw) {
  return String(raw || "item").replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 80);
}

/**
 * Extracts all product/variant entries that have reached <= 30% of their
 * original physical stock, plus all active item keys so restocked items can
 * be cleared from unsent daily logs.
 * @param {string} productId Product document ID.
 * @param {Object} data Product document data.
 * @param {Object} [beforeData] Optional prior product document data.
 * @return {{breached: Array<{itemKey: string, payload: Object}>,
 *   recoveredKeys: Array<string>}} Evaluated entries.
 */
function evaluateLowStockForProduct(productId, data, beforeData = null) {
  if (!data || data.status === "archived") {
    return {breached: [], recoveredKeys: []};
  }

  const categoryName = String(data.category || "Others").trim() || "Others";
  const productName = String(data.name || "Unnamed Product").trim() ||
    "Unnamed Product";
  const unit = String(data.unit || "pcs").trim() || "pcs";
  const isVariantsArray = Array.isArray(data.variants);
  const isVariantsMap =
    !isVariantsArray &&
    data.variants !== null &&
    typeof data.variants === "object" &&
    Object.keys(data.variants).length > 0;
  const variantEntries = isVariantsArray ?
    data.variants.map((v, idx) => ({
      key: String((v && v.id) || `var_${idx}`),
      value: v || {},
    })) :
    (isVariantsMap ?
      Object.entries(data.variants).map(([k, v]) => ({
        key: String(k),
        value: v || {},
      })) :
      []);

  const beforeVariantsByKey = {};
  if (beforeData && beforeData.variants) {
    if (Array.isArray(beforeData.variants)) {
      beforeData.variants.forEach((bv, idx) => {
        const bKey = String((bv && bv.id) || `var_${idx}`);
        beforeVariantsByKey[bKey] = bv || {};
      });
    } else if (typeof beforeData.variants === "object") {
      Object.entries(beforeData.variants).forEach(([k, bv]) => {
        beforeVariantsByKey[String(k)] = bv || {};
      });
    }
  }

  const breached = [];
  const recoveredKeys = [];

  if (variantEntries.length > 0) {
    variantEntries.forEach(({key, value: v}, idx) => {
      const vId = String(v.id || key || `var_${idx}`);
      const itemKey = `${productId}__${vId}`;
      const prevVar = beforeVariantsByKey[vId] || beforeVariantsByKey[key];
      const vStock = Math.max(0, Math.floor(Number(v.stock) || 0));
      const vReserved = Math.max(0, Math.floor(Number(v.reservedStock) || 0));
      const vAvail = Math.max(0, vStock - vReserved);
      const vOriginal = resolveOriginalStock(vStock, v.initialStock, {
        physicalReserve: v.physicalReserve,
        previousStock: prevVar ? prevVar.stock : 0,
      });
      const vTrigger = calculateLowStockTrigger(vOriginal);
      const vReserve = resolvePhysicalReserve(vOriginal, v.physicalReserve);
      const vOnlineAvail = calculateOnlineAvailable(vAvail, vReserve);
      const vOnlineOos = vOnlineAvail <= 0;
      const vPhysicalHit = vOriginal > 0 && vAvail <= vTrigger;

      if (vPhysicalHit) {
        const vName = String(v.name || `Variant ${idx + 1}`);
        const restockQty = calculateSuggestedRestock(vAvail, vOriginal);
        breached.push({
          itemKey,
          payload: {
            productId,
            variantId: vId,
            productName,
            variantName: vName,
            category: categoryName,
            unit,
            originalStock: vOriginal,
            lowStockThreshold: vTrigger,
            physicalStock: vAvail,
            onlineStock: vOnlineAvail,
            totalStock: vStock,
            availableStock: vAvail,
            suggestedResupplyQty: restockQty,
            onlineOutOfStock: vOnlineOos,
          },
        });
      } else {
        recoveredKeys.push(itemKey);
      }
    });
  } else {
    const stock = Math.max(0, Math.floor(Number(data.stock) || 0));
    const reserved = Math.max(0, Math.floor(Number(data.reservedStock) || 0));
    const avail = Math.max(0, stock - reserved);
    const original = resolveOriginalStock(stock, data.initialStock, {
      batches: data.batches,
      physicalReserve: data.physicalReserve,
      previousStock: beforeData ? beforeData.stock : 0,
    });
    const trigger = calculateLowStockTrigger(original);
    const reserve = resolvePhysicalReserve(original, data.physicalReserve);
    const onlineAvail = calculateOnlineAvailable(avail, reserve);
    const onlineOos = onlineAvail <= 0;
    const physicalHit = original > 0 && avail <= trigger;

    if (physicalHit) {
      const restockQty = calculateSuggestedRestock(avail, original);
      breached.push({
        itemKey: productId,
        payload: {
          productId,
          productName,
          category: categoryName,
          unit,
          originalStock: original,
          lowStockThreshold: trigger,
          physicalStock: avail,
          onlineStock: onlineAvail,
          totalStock: stock,
          availableStock: avail,
          suggestedResupplyQty: restockQty,
          onlineOutOfStock: onlineOos,
        },
      });
    } else {
      recoveredKeys.push(productId);
    }
  }

  return {breached, recoveredKeys};
}

/**
 * Scans all active products and ensures every item currently at <= 30% of
 * its original stock is captured in `daily_resupply_logs/{dateKey}` (and any
 * restocked items are removed if unsent) before dispatching the store-closing
 * summary email.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {string} dateKey Store calendar date key (YYYY-MM-DD).
 * @return {Promise<number>} Count of low-stock items synced.
 */
async function syncCurrentlyLowStockProducts(db, dateKey) {
  const productsSnap = await db.collection("products").get();
  let count = 0;
  for (const doc of productsSnap.docs) {
    const {breached, recoveredKeys} = evaluateLowStockForProduct(
        doc.id,
        doc.data() || {},
    );
    for (const entry of breached) {
      await upsertDailyResupplyItem(db, dateKey, entry.itemKey, entry.payload);
      count++;
    }
    for (const recoveredKey of recoveredKeys) {
      await removeDailyResupplyItem(db, dateKey, recoveredKey);
    }
  }
  return count;
}

/**
 * Extracts calendar and time components in Asia/Manila (UTC+8).
 * @param {Date} [date] Optional Date instance.
 * @return {{year: number, month: number, day: number,
 *   hour: number, minute: number}} Manila date/time components.
 */
function getManilaParts(date) {
  const base = date || new Date();
  const ms = base.getTime() + (8 * 60 * 60 * 1000);
  const m = new Date(ms);
  return {
    year: m.getUTCFullYear(),
    month: m.getUTCMonth() + 1,
    day: m.getUTCDate(),
    hour: m.getUTCHours(),
    minute: m.getUTCMinutes(),
  };
}

/**
 * Formats Manila date parts as YYYY-MM-DD.
 * @param {{year: number, month: number, day: number}} parts Date parts.
 * @return {string} YYYY-MM-DD key.
 */
function formatDateKeyFromParts(parts) {
  const y = String(parts.year).padStart(4, "0");
  const m = String(parts.month).padStart(2, "0");
  const d = String(parts.day).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/**
 * Returns the YYYY-MM-DD date key in Asia/Manila timezone.
 * @param {Date} [date] Optional Date instance.
 * @return {string} Manila date key.
 */
function getManilaDateKey(date) {
  return formatDateKeyFromParts(getManilaParts(date));
}

/**
 * Parses a "HH:mm" close time string (default 21:00).
 * @param {string} rawCloseTime Raw close time string.
 * @return {{hour: number, minute: number}} Parsed hour and minute.
 */
function parseCloseTime(rawCloseTime) {
  const str = String(rawCloseTime || "21:00").trim();
  const parts = str.split(":");
  const hour = Number(parts[0]);
  const minute = Number(parts[1]);
  if (
    Number.isInteger(hour) &&
    Number.isInteger(minute) &&
    hour >= 0 &&
    hour <= 23 &&
    minute >= 0 &&
    minute <= 59
  ) {
    return {hour, minute};
  }
  return {hour: 21, minute: 0};
}

/**
 * Escapes HTML special characters.
 * @param {*} raw Input value.
 * @return {string} Escaped string.
 */
function escapeHtml(raw) {
  return String(raw || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
}

/**
 * Sends an email to the GDC Sari-Sari Store Gmail account via Brevo API.
 * If `BREVO_API_KEY` is not configured in Cloud Functions, returns
 * `{sent: false, pendingClient: true}` instead of falsely marking sent so the
 * Admin App (which holds the Brevo API key) dispatches the email immediately.
 * @param {{subject: string, html: string, text: string}} payload Email payload.
 * @return {Promise<Object>} Delivery outcome object.
 */
async function sendStoreGmailAlert({subject, html, text}) {
  const brevoKey = (process.env.BREVO_API_KEY || "").trim();

  if (!brevoKey) {
    console.warn(
        "BREVO_API_KEY is not configured in Cloud Functions; leaving " +
        "daily resupply summary pending for Admin App Brevo dispatch.",
    );
    return {
      sent: false,
      pendingClient: true,
      error: "BREVO_API_KEY is not configured in Cloud Functions",
    };
  }

  try {
    const resp = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: {
        "accept": "application/json",
        "api-key": brevoKey,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        sender: {name: "GDC Store", email: STORE_GMAIL_ADDRESS},
        to: [{email: STORE_GMAIL_ADDRESS, name: "GDC Sari-Sari Store"}],
        replyTo: {email: STORE_GMAIL_ADDRESS, name: "GDC Store"},
        subject,
        htmlContent: html,
        textContent: text,
      }),
    });
    if (resp.ok) {
      console.log(`Brevo email sent to ${STORE_GMAIL_ADDRESS}: ${subject}`);
      return {sent: true};
    }
    const errText = await resp.text();
    console.error(`Brevo email failed [${resp.status}]:`, errText);
    return {sent: false, error: `Brevo [${resp.status}]: ${errText}`};
  } catch (err) {
    console.error("Error dispatching Brevo email:", err);
    return {sent: false, error: String(err)};
  }
}

/**
 * Transactionally records or updates a breached item in
 * `daily_resupply_logs/{dateKey}`.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {string} dateKey Store calendar date key (YYYY-MM-DD).
 * @param {string} itemKey Unique product or product__variant key.
 * @param {Object} itemPayload Resupply snapshot payload.
 * @return {Promise<{isNewToday: boolean, escalatedToOos: boolean}>} Result.
 */
async function upsertDailyResupplyItem(db, dateKey, itemKey, itemPayload) {
  const logRef = db.collection("daily_resupply_logs").doc(dateKey);
  const nowTs = admin.firestore.Timestamp.now();

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(logRef);
    const existing = snap.exists ? (snap.data() || {}) : {};
    const itemsMap = Object.assign({}, existing.items || {});
    const prevItem = itemsMap[itemKey];
    const isNewToday = !prevItem;
    const prevAvail = prevItem ? Number(prevItem.availableStock) : -1;
    const nextAvail = Number(itemPayload.availableStock) || 0;
    const escalatedToOos = !isNewToday && prevAvail > 0 && nextAvail <= 0;

    const firstTriggeredAt =
      prevItem && prevItem.firstTriggeredAt ?
        prevItem.firstTriggeredAt :
        nowTs;

    itemsMap[itemKey] = Object.assign({}, itemPayload, {
      firstTriggeredAt,
      lastUpdatedAt: nowTs,
    });

    if (!snap.exists) {
      tx.set(logRef, {
        dateKey,
        storeEmail: STORE_GMAIL_ADDRESS,
        items: itemsMap,
        itemCount: Object.keys(itemsMap).length,
        summaryEmailSent: false,
        summaryEmailStatus: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      tx.set(
          logRef,
          {
            dateKey,
            storeEmail: existing.storeEmail || STORE_GMAIL_ADDRESS,
            items: itemsMap,
            itemCount: Object.keys(itemsMap).length,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true},
      );
    }

    return {isNewToday, escalatedToOos};
  });
}

/**
 * Removes a restocked item from `daily_resupply_logs/{dateKey}` if the daily
 * summary email has not yet been sent.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {string} dateKey Store calendar date key (YYYY-MM-DD).
 * @param {string} itemKey Unique product or product__variant key.
 * @return {Promise<void>}
 */
async function removeDailyResupplyItem(db, dateKey, itemKey) {
  const logRef = db.collection("daily_resupply_logs").doc(dateKey);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(logRef);
    if (!snap.exists) return;
    const existing = snap.data() || {};
    if (existing.summaryEmailSent === true) return;
    const itemsMap = Object.assign({}, existing.items || {});
    if (!(itemKey in itemsMap)) return;
    delete itemsMap[itemKey];
    tx.set(
        logRef,
        {
          dateKey,
          storeEmail: existing.storeEmail || STORE_GMAIL_ADDRESS,
          items: itemsMap,
          itemCount: Object.keys(itemsMap).length,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
    );
  });
}

/**
 * Builds the HTML table row for a single resupply item.
 * @param {Object} it DailyResupplyItem object.
 * @return {string} HTML table row string.
 */
function buildResupplyRowHtml(it) {
  const displayName = it.variantName ?
    `${it.productName} (${it.variantName})` :
    (it.productName || "Unnamed Product");
  const avail = Math.max(0, Number(it.availableStock) || 0);
  const orig = Math.max(
      Number(it.originalStock) || 0,
      Number(it.totalStock) || 0,
      avail,
  );
  const thresh = Math.max(
      0,
      Number(it.lowStockThreshold) || calculateLowStockTrigger(orig),
  );
  const resupply = Math.max(1, Number(it.suggestedResupplyQty) || 1);
  const unit = escapeHtml(it.unit || "pcs");
  const onlineLabel = it.onlineOutOfStock ?
    "<span style=\"color:#dc2626;font-weight:bold;\">Out of Stock</span>" :
    `${Math.max(0, Number(it.onlineStock) || 0)} ${unit}`;
  const stockColor = avail <= 0 ? "#dc2626" : "#d97706";
  const tdBase = "padding:10px;border-bottom:1px solid #e5e7eb;";

  return [
    "<tr>",
    `<td style="${tdBase}"><strong>${escapeHtml(displayName)}</strong><br>`,
    "<span style=\"font-size:12px;color:#6b7280;\">",
    `${escapeHtml(it.category || "Others")}</span></td>`,
    `<td style="${tdBase}text-align:center;color:${stockColor};`,
    `font-weight:bold;">${avail} / ${orig} ${unit}</td>`,
    `<td style="${tdBase}text-align:center;">&le; ${thresh} ${unit}</td>`,
    `<td style="${tdBase}text-align:center;">${onlineLabel}</td>`,
    `<td style="${tdBase}text-align:center;font-weight:bold;`,
    `color:#1d4ed8;">+${resupply} ${unit}</td>`,
    "</tr>",
  ].join("");
}

/**
 * Atomically claims and dispatches the Store-Closing Resupply Summary Email
 * for `daily_resupply_logs/{dateKey}` if it has items and has not yet been
 * sent.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {string} dateKey Store calendar date key (YYYY-MM-DD).
 * @param {string} triggeredBy Dispatcher label for audit fields.
 * @return {Promise<boolean>} True if an email was sent.
 */
async function dispatchDailyResupplySummaryForDate(db, dateKey, triggeredBy) {
  const logRef = db.collection("daily_resupply_logs").doc(dateKey);
  const claimResult = await db.runTransaction(async (tx) => {
    const snap = await tx.get(logRef);
    if (!snap.exists) {
      return {claimed: false, reason: "no_log"};
    }
    const data = snap.data() || {};
    const itemsObj = data.items || {};
    const itemKeys = Object.keys(itemsObj);
    if (itemKeys.length === 0) {
      return {claimed: false, reason: "empty"};
    }
    if (data.summaryEmailSent === true) {
      return {claimed: false, reason: "already_sent"};
    }
    if (data.summaryEmailStatus === "sending" && data.summaryEmailClaimedAt) {
      const claimedMs = data.summaryEmailClaimedAt.toMillis ?
        data.summaryEmailClaimedAt.toMillis() :
        0;
      if (Date.now() - claimedMs < 5 * 60 * 1000) {
        return {claimed: false, reason: "in_flight"};
      }
    }

    tx.set(
        logRef,
        {
          summaryEmailStatus: "sending",
          summaryEmailClaimedAt: admin.firestore.FieldValue.serverTimestamp(),
          summaryEmailSentBy: triggeredBy,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
    );

    return {
      claimed: true,
      storeEmail: data.storeEmail || STORE_GMAIL_ADDRESS,
      items: itemKeys.map((k) => Object.assign({itemKey: k}, itemsObj[k])),
    };
  });

  if (!claimResult.claimed) {
    return false;
  }

  const items = claimResult.items.sort((a, b) => {
    const diff =
      (Number(a.availableStock) || 0) - (Number(b.availableStock) || 0);
    if (diff !== 0) return diff;
    return String(a.productName || "").localeCompare(
        String(b.productName || ""),
    );
  });

  const totalSuggested = items.reduce(
      (acc, it) => acc + Math.max(0, Number(it.suggestedResupplyQty) || 0),
      0,
  );
  const outOfStockCount = items.filter(
      (it) => (Number(it.availableStock) || 0) <= 0,
  ).length;

  const rowsHtml = items.map(buildResupplyRowHtml).join("");
  const plural = items.length === 1 ? "" : "s";
  const unitPlural = totalSuggested === 1 ? "" : "s";

  const subject =
    `📦 Store-Closing Resupply Summary (${dateKey}) — ` +
    `${items.length} Product${plural} Reached 30% Stock`;

  const thStyle = "padding:10px;border-bottom:2px solid #d1d5db;";
  const html = [
    "<div style=\"font-family:Arial,sans-serif;max-width:680px;",
    "margin:0 auto;color:#111827;\">",
    "<div style=\"background:#0f766e;color:#ffffff;padding:20px 24px;",
    "border-radius:12px 12px 0 0;\">",
    "<h2 style=\"margin:0;font-size:20px;\">",
    "GDC Sari-Sari Store — Store-Closing Resupply Summary</h2>",
    "<p style=\"margin:6px 0 0;font-size:13px;opacity:0.9;\">",
    `Store Date: ${escapeHtml(dateKey)} • ${items.length} item${plural} `,
    `at &le; 30% of original stock (${outOfStockCount} out of stock)`,
    "</p></div>",
    "<div style=\"border:1px solid #e5e7eb;border-top:none;",
    "padding:20px 24px;border-radius:0 0 12px 12px;background:#ffffff;\">",
    "<p style=\"margin-top:0;font-size:14px;line-height:1.5;\">",
    "The store has closed for the day. The following products reached ",
    "<strong>30% or less of their original physical stock</strong> today. ",
    "The 25% walk-in physical reserve stays protected for in-store POS ",
    "sales while Online Store listings show <strong>Out of Stock</strong> ",
    "once the 75% online allocation is depleted.</p>",
    "<table style=\"width:100%;border-collapse:collapse;font-size:13px;",
    "margin:16px 0;\"><thead><tr style=\"background:#f3f4f6;",
    "text-align:left;\">",
    `<th style="${thStyle}">Product</th>`,
    `<th style="${thStyle}text-align:center;">Physical / Original</th>`,
    `<th style="${thStyle}text-align:center;">30% Alert</th>`,
    `<th style="${thStyle}text-align:center;">Online Store</th>`,
    `<th style="${thStyle}text-align:center;">Suggested Resupply</th>`,
    `</tr></thead><tbody>${rowsHtml}</tbody></table>`,
    "<div style=\"background:#f8fafc;border:1px solid #e2e8f0;",
    "border-radius:10px;padding:12px 14px;font-size:13px;\">",
    "<strong>Total Suggested Resupply Quantity:</strong> ",
    `${totalSuggested} unit${unitPlural} across ${items.length} `,
    `item${plural}.</div></div></div>`,
  ].join("");

  const textLines = items.map((it) => {
    const displayName = it.variantName ?
      `${it.productName} (${it.variantName})` :
      (it.productName || "Unnamed Product");
    const onlineTxt = it.onlineOutOfStock ? "Out of Stock" : it.onlineStock;
    const orig = Math.max(
        Number(it.originalStock) || 0,
        Number(it.totalStock) || 0,
        Number(it.availableStock) || 0,
    );
    const unit = it.unit || "pcs";
    return `- ${displayName}: ${it.availableStock}/${orig} ${unit} ` +
      `(30% Alert: <= ${it.lowStockThreshold}) | Online: ${onlineTxt} | ` +
      `Suggested Resupply: +${it.suggestedResupplyQty}`;
  });
  const text =
    `GDC Sari-Sari Store — Store-Closing Resupply Summary (${dateKey})\n` +
    `${items.length} product(s) reached <= 30% of original stock:\n\n` +
    textLines.join("\n") +
    `\n\nTotal Suggested Resupply Units: ${totalSuggested}`;

  try {
    const delivery = await sendStoreGmailAlert({subject, html, text});
    if (!delivery.sent) {
      await logRef.set(
          {
            summaryEmailSent: false,
            summaryEmailStatus: delivery.pendingClient ?
              "pending_client" :
              "failed",
            summaryEmailError: delivery.error || "Email dispatch failed",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true},
      );
      return false;
    }

    await logRef.set(
        {
          summaryEmailSent: true,
          summaryEmailStatus: "sent",
          summaryEmailSentAt: admin.firestore.FieldValue.serverTimestamp(),
          summaryEmailSentBy: triggeredBy,
          summaryEmailError: null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
    );

    const previewNames = items.slice(0, 3).map((it) =>
      it.variantName ?
        `${it.productName} (${it.variantName})` :
        (it.productName || "Unnamed Product"),
    );
    const extraCount = items.length - previewNames.length;
    const extraSuffix = extraCount > 0 ? ` +${extraCount} more` : "";
    const itemsPreview = previewNames.length > 0 ?
      ` (${previewNames.join(", ")}${extraSuffix})` :
      "";
    const notifMessage =
      `Store-Closing Resupply Summary emailed to ${claimResult.storeEmail} ` +
      `for ${items.length} low-stock item${plural}${itemsPreview} ` +
      `at <= 30% stock (${dateKey}).`;
    await db
        .collection("admin_notifications")
        .doc(`eod_resupply_${sanitizeDocIdSegment(dateKey)}`)
        .set(
            {
              type: "daily_resupply_summary",
              title: `📧 Store-Closing Resupply Email Sent (${dateKey})`,
              message: notifMessage,
              body: notifMessage,
              severity: "info",
              status: `${items.length} items summarized`,
              relatedId: dateKey,
              dateKey,
              itemCount: items.length,
              isRead: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

    await admin.messaging().send({
      notification: {
        title: `Store-Closing Resupply Email Sent (${dateKey})`,
        body: notifMessage,
      },
      data: {
        recipient: "admin",
        type: "daily_resupply_summary",
        dateKey,
      },
      topic: "admin_alerts",
    }).catch((err) => console.error("FCM error:", err));

    return true;
  } catch (err) {
    console.error(
        `Failed sending store-closing resupply email for ${dateKey}:`,
        err,
    );
    await logRef.set(
        {
          summaryEmailSent: false,
          summaryEmailStatus: "failed",
          summaryEmailError: String(err),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
    );
    return false;
  }
}

/**
 * Physical Low-Stock (30% of Original Stock) Monitor Trigger.
 * - Uses the fixed 100% POS / 75% Online (25% physical-only reserve) model.
 * - Fires an immediate Inventory Alert + FCM notification whenever 100%
 *   physical stock reaches <= 30% of original stock (or escalates to OOS),
 *   and upserts the item into `daily_resupply_logs/{YYYY-MM-DD}` for the
 *   Store-Closing Email. Removes restocked items from unsent daily logs.
 */
exports.onProductStockThresholdCheck = onDocumentUpdated(
    "products/{productId}",
    async (event) => {
      const before = event.data.before.data() || {};
      const after = event.data.after.data() || {};
      const productId = event.params.productId;

      const stockChanged =
        before.stock !== after.stock ||
        before.reservedStock !== after.reservedStock ||
        before.initialStock !== after.initialStock ||
        before.physicalReserve !== after.physicalReserve ||
        JSON.stringify(before.variants || null) !==
          JSON.stringify(after.variants || null);

      if (!stockChanged) return;
      if (after.status === "archived") return;

      const db = admin.firestore();
      const todayKey = getManilaDateKey(new Date());
      const {breached, recoveredKeys} = evaluateLowStockForProduct(
          productId,
          after,
          before,
      );

      for (const recoveredKey of recoveredKeys) {
        await removeDailyResupplyItem(db, todayKey, recoveredKey);
      }

      for (const entry of breached) {
        const {isNewToday, escalatedToOos} = await upsertDailyResupplyItem(
            db,
            todayKey,
            entry.itemKey,
            entry.payload,
        );
        if (!isNewToday && !escalatedToOos) continue;

        const p = entry.payload;
        const label = p.variantName ?
          `${p.productName} (${p.variantName})` :
          p.productName;
        const isCritical = p.availableStock <= 0;
        const title = isCritical ?
          `🚨 Out of Stock: ${label}` :
          `⚠️ Low Stock (30%): ${label}`;
        const body = isCritical ?
          `${label} is out of stock (0/${p.originalStock} ${p.unit}; ` +
            `30% alert: <= ${p.lowStockThreshold}). Online Store is ` +
            "Out of Stock. Queued for End-of-Day Resupply Email." :
          `${label} is low on stock ` +
            `(${p.availableStock}/${p.originalStock} ${p.unit} left; ` +
            `30% alert: <= ${p.lowStockThreshold}). Queued for ` +
            `End-of-Day Resupply Email (+${p.suggestedResupplyQty} ` +
            `${p.unit}).`;

        const notifDocId =
          `low30_${todayKey}_${sanitizeDocIdSegment(entry.itemKey)}_` +
          `${isCritical ? "oos" : "low"}`;

        await db
            .collection("admin_notifications")
            .doc(notifDocId)
            .set(
                {
                  type: isCritical ?
                    "out_of_stock" :
                    "physical_low_stock_alert",
                  title,
                  message: body,
                  body,
                  relatedId: p.productId,
                  productId: p.productId,
                  variantId: p.variantId || null,
                  severity: isCritical ? "critical" : "warning",
                  status: isCritical ?
                    "Out of Stock" :
                    `Low Stock <= 30% (${p.availableStock}/${p.originalStock})`,
                  suggestedRestock: p.suggestedResupplyQty,
                  isRead: false,
                  createdAt: admin.firestore.FieldValue.serverTimestamp(),
                },
                {merge: true},
            );

        await admin.messaging().send({
          notification: {title, body},
          data: {
            recipient: "admin",
            type: isCritical ? "out_of_stock" : "physical_low_stock_alert",
            productId: p.productId,
          },
          topic: "admin_alerts",
        }).catch((err) => console.error("FCM error:", err));
      }
    },
);

/**
 * Immediate Store-Closing Trigger.
 * Fires whenever `settings/store_settings` transitions to closed for the day
 * (e.g., admin manually closes the store or sets closing hours/overrides),
 * syncing all items currently at <= 30% of original stock and dispatching
 * ONE Store-Closing Resupply Summary Email for today.
 */
exports.onStoreSettingsClosed = onDocumentUpdated(
    "settings/store_settings",
    async (event) => {
      const before = event.data.before.data() || {};
      const after = event.data.after.data() || {};
      const now = new Date();
      const manilaNow = getManilaParts(now);

      const wasClosed = hasStoreClosedForDay(before, manilaNow, now);
      const isNowClosed = hasStoreClosedForDay(after, manilaNow, now);
      const newlyManualClosed =
        before.isClosed !== true && after.isClosed === true;

      if (!isNowClosed || (wasClosed && !newlyManualClosed)) {
        return;
      }

      const db = admin.firestore();
      const todayKey = formatDateKeyFromParts(manilaNow);
      await syncCurrentlyLowStockProducts(db, todayKey);
      await dispatchDailyResupplySummaryForDate(
          db,
          todayKey,
          "store_closed_trigger",
      );
    },
);

/**
 * Store-Closing Resupply Summary Email Scheduler (runs every 15 minutes in
 * Asia/Manila). Checks whether the store has closed for the day (manual close,
 * scheduled outage, special-hours override end time, or regular
 * `dailyCloseTime`) and sends ONE consolidated email summarizing all products
 * that reached <= 30% of their original stock.
 */
exports.sendDailyResupplySummaryEmail = onSchedule(
    {
      schedule: "*/15 * * * *",
      timeZone: "Asia/Manila",
    },
    async () => {
      const db = admin.firestore();
      const now = new Date();
      const manilaNow = getManilaParts(now);
      const todayKey = formatDateKeyFromParts(manilaNow);
      const yesterdayKey = getManilaDateKey(
          new Date(now.getTime() - (24 * 60 * 60 * 1000)),
      );

      await dispatchDailyResupplySummaryForDate(
          db,
          yesterdayKey,
          "cloud_scheduler_catchup",
      );

      const settingsSnap = await db
          .collection("settings")
          .doc("store_settings")
          .get();
      const settingsData = settingsSnap.exists ?
        (settingsSnap.data() || {}) :
        {};

      if (hasStoreClosedForDay(settingsData, manilaNow, now)) {
        await syncCurrentlyLowStockProducts(db, todayKey);
        await dispatchDailyResupplySummaryForDate(
            db,
            todayKey,
            "cloud_scheduler_store_close",
        );
      }
    },
);
