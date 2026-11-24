import 'package:cloud_firestore/cloud_firestore.dart';

/// Standard FIFO batch lifecycle status values stored in Firestore.
class BatchStatus {
  static const String active = 'ACTIVE';
  static const String depleted = 'DEPLETED';
  static const String expired = 'EXPIRED';
  static const String archived = 'ARCHIVED';
}

/// Represents a distinct delivery lot/batch of a single product stored under
/// `products/{productId}/batches/{batchId}` for First-In, First-Out (FIFO)
/// inventory management.
class ProductBatch {
  /// Unique human-readable batch identifier (e.g., `BATCH-20261124-A1B2` or `LEGACY-INIT`).
  final String batchId;

  /// Parent product document ID.
  final String productId;

  /// Denormalized product name for fast audit & UI display.
  final String productName;

  /// Supplier document ID (from PO or manual selection), if known.
  final String? supplierId;

  /// Supplier display name, if known.
  final String? supplierName;

  /// Purchase Order document ID if received via supplier PO workflow.
  final String? poId;

  /// Human-readable Purchase Order number (e.g., `PO-2026-001`), if applicable.
  final String? poNumber;

  /// Date the stock was ordered/purchased from the supplier.
  final DateTime datePurchased;

  /// Date the stock physically arrived and was checked into inventory.
  /// Secondary FIFO sort key (`dateArrived ASC`) after `expiryDate ASC`.
  final DateTime dateArrived;

  /// Optional expiration date for perishable goods.
  final DateTime? expiryDate;

  /// Unit supplier cost for this specific batch.
  final double costPrice;

  /// Total units originally received in this batch.
  final int initialQty;

  /// Current unsold units remaining in this batch.
  final int remainingQty;

  /// Lifecycle status: `"ACTIVE"` (`remainingQty > 0` & not expired),
  /// `"DEPLETED"` (`remainingQty == 0`), `"EXPIRED"` (past `expiryDate`),
  /// or `"ARCHIVED"`.
  final String status;

  /// Supplier invoice or delivery receipt reference number (optional).
  final String? invoiceNumber;

  /// Creates a new [ProductBatch] instance.
  ///
  /// Preserves legacy constructor parameter aliases (`id`, `quantityRemaining`,
  /// `quantity`, `unitCost`, `dateReceived`, `createdAt`, `expirationDate`) so
  /// existing code continues working with zero breaking changes.
  ProductBatch({
    String? batchId,
    String? id,
    required this.productId,
    this.productName = '',
    this.supplierId,
    this.supplierName,
    this.poId,
    this.poNumber,
    DateTime? datePurchased,
    DateTime? dateArrived,
    DateTime? dateReceived,
    DateTime? createdAt,
    DateTime? expiryDate,
    DateTime? expirationDate,
    double? costPrice,
    double? unitCost,
    int? initialQty,
    int? remainingQty,
    int? quantityRemaining,
    int? quantity,
    String? status,
    this.invoiceNumber,
  })  : batchId = batchId ?? id ?? '',
        dateArrived =
            dateArrived ?? dateReceived ?? createdAt ?? DateTime.now(),
        datePurchased = datePurchased ??
            dateArrived ??
            dateReceived ??
            createdAt ??
            DateTime.now(),
        expiryDate = expiryDate ?? expirationDate,
        costPrice = costPrice ?? unitCost ?? 0.0,
        remainingQty = _clampNonNegative(
            remainingQty ?? quantityRemaining ?? quantity ?? 0),
        initialQty = _clampNonNegative(
            initialQty ?? remainingQty ?? quantityRemaining ?? quantity ?? 0),
        status = _normalizeStatus(
          status,
          _clampNonNegative(remainingQty ?? quantityRemaining ?? quantity ?? 0),
        );

  static int _clampNonNegative(int value) => value < 0 ? 0 : value;

  static String _normalizeStatus(String? rawStatus, int remQty) {
    final upper = rawStatus?.trim().toUpperCase();
    if (upper == BatchStatus.archived) return BatchStatus.archived;
    if (upper == BatchStatus.depleted || remQty <= 0) {
      return BatchStatus.depleted;
    }
    if (upper == BatchStatus.expired) return BatchStatus.expired;
    return BatchStatus.active;
  }

  // ── Backwards-compatible aliases ──────────────────────────────────────────
  String get id => batchId;
  int get quantityRemaining => remainingQty;
  int get quantity => remainingQty;
  double get unitCost => costPrice;
  DateTime get dateReceived => dateArrived;
  DateTime get createdAt => dateArrived;
  DateTime? get expirationDate => expiryDate;

  // ── Unified "Sellable Stock" Single-Source-of-Truth Rule ──────────────────

  /// Evaluates whether this batch is expired as of [now].
  /// A batch is expired if its stored status is `EXPIRED` or its `expiryDate`
  /// is not strictly after [now].
  bool isExpiredAt(DateTime now) {
    if (status.trim().toUpperCase() == BatchStatus.expired) return true;
    if (expiryDate == null) return false;
    return !expiryDate!.isAfter(now);
  }

  /// Evaluates the unified "Sellable Stock" rule as of [now]:
  /// - Batch status == `'ACTIVE'` (case-insensitive)
  /// - `remainingQty > 0`
  /// - Not expired (`expirationDate == null || expirationDate.isAfter(now)`)
  bool isSellableAt(DateTime now) {
    if (status.trim().toUpperCase() != BatchStatus.active) return false;
    if (remainingQty <= 0) return false;
    if (expiryDate != null && !expiryDate!.isAfter(now)) return false;
    return true;
  }

  /// Unified "Sellable Stock" getter evaluated against [DateTime.now].
  bool get isSellable => isSellableAt(DateTime.now());

  /// Alias for [isSellable] so all active-batch checks enforce the exact same
  /// sellable rule (status == ACTIVE, remainingQty > 0, and not expired).
  bool get isActive => isSellable;

  bool get isDepleted =>
      status.trim().toUpperCase() == BatchStatus.depleted || remainingQty <= 0;

  bool get isArchived => status.trim().toUpperCase() == BatchStatus.archived;

  /// Resolves the canonical Firestore lifecycle status for this batch at [now]:
  /// - `ARCHIVED` stays `ARCHIVED`
  /// - `remainingQty == 0` -> `DEPLETED`
  /// - Past `expiryDate` (or already `EXPIRED`) -> `EXPIRED`
  /// - Otherwise -> `ACTIVE`
  String effectiveStatusAt(DateTime now) {
    final upper = status.trim().toUpperCase();
    if (upper == BatchStatus.archived) return BatchStatus.archived;
    if (remainingQty <= 0 || upper == BatchStatus.depleted) {
      return BatchStatus.depleted;
    }
    if (upper == BatchStatus.expired ||
        (expiryDate != null && !expiryDate!.isAfter(now))) {
      return BatchStatus.expired;
    }
    return BatchStatus.active;
  }

  /// Returns a normalized copy with non-negative `remainingQty` and up-to-date
  /// lifecycle `status` (`DEPLETED` if 0, `EXPIRED` if past expiration).
  ProductBatch normalizedForPersistence({DateTime? now}) {
    final effectiveNow = now ?? DateTime.now();
    final safeRem = remainingQty < 0 ? 0 : remainingQty;
    final safeInit = initialQty < safeRem ? safeRem : initialQty;
    final nextStatus = effectiveStatusAt(effectiveNow);
    if (safeRem == remainingQty &&
        safeInit == initialQty &&
        nextStatus == status) {
      return this;
    }
    return copyWith(
      initialQty: safeInit,
      remainingQty: safeRem,
      status: nextStatus,
    );
  }

  /// Sums `remainingQty` across all sellable batches using the unified rule.
  static int sumSellableStock(
    Iterable<ProductBatch> batches, {
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    return batches
        .where((b) => b.isSellableAt(effectiveNow))
        .fold<int>(0, (acc, b) => acc + b.remainingQty);
  }

  /// True when this batch is explicitly linked to a non-empty supplier ID.
  bool get hasValidSupplier =>
      supplierId != null && supplierId!.trim().isNotEmpty;

  /// True when this batch originated from a Supplier Purchase Order.
  bool get hasPoLink =>
      (poId != null && poId!.trim().isNotEmpty) ||
      (poNumber != null && poNumber!.trim().isNotEmpty);

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Returns true when [id] is a legacy v4 UUID generated before human-readable
  /// PO/BATCH identifiers were introduced.
  static bool isLegacyUuid(String id) => _uuidRegex.hasMatch(id.trim());

  bool get isLegacyUuidId => isLegacyUuid(batchId);

  /// Human-readable batch code that converts raw 36-char legacy UUIDs into a
  /// concise `LEGACY-XXXXXXXX` label without mutating the underlying Firestore
  /// document ID ([batchId]).
  static String formatBatchIdForDisplay(String rawBatchId) {
    final trimmed = rawBatchId.trim();
    if (trimmed.isEmpty) return 'UNKNOWN-BATCH';
    if (isLegacyUuid(trimmed)) {
      return 'LEGACY-${trimmed.substring(0, 8).toUpperCase()}';
    }
    return trimmed;
  }

  /// Normalized PO number display string (avoids duplicate `PO #PO-...` prefixes).
  static String formatPoNumber(String rawPoNumber) {
    final trimmed = rawPoNumber.trim().replaceFirst(RegExp(r'^#+'), '');
    if (trimmed.isEmpty) return '';
    if (RegExp(r'^PO[\s#-]', caseSensitive: false).hasMatch(trimmed)) {
      return trimmed.toUpperCase();
    }
    return 'PO-$trimmed';
  }

  String get displayBatchId => formatBatchIdForDisplay(batchId);

  /// Primary reference label shown in Batch Views: uses the PO order number
  /// whenever linked to a Purchase Order, otherwise falls back to [displayBatchId].
  String primaryReference({String? resolvedPoNumber}) {
    final effectivePo =
        (resolvedPoNumber != null && resolvedPoNumber.trim().isNotEmpty)
            ? resolvedPoNumber.trim()
            : (poNumber != null && poNumber!.trim().isNotEmpty
                ? poNumber!.trim()
                : null);
    if (effectivePo != null) {
      return formatPoNumber(effectivePo);
    }
    return displayBatchId;
  }

  /// FIFO/FEFO comparator:
  /// 1. Earliest non-null `expiryDate` first (perishable lots prioritized before
  ///    non-expiring lots so older-expiring inventory sells first).
  /// 2. Oldest arrived batch (`dateArrived` / `createdAt` ASC).
  /// 3. `batchId ASC` as deterministic tie-breaker.
  static int compareFifo(ProductBatch a, ProductBatch b) {
    final expA = a.expiryDate;
    final expB = b.expiryDate;
    if (expA != null && expB != null) {
      final expCmp = expA.compareTo(expB);
      if (expCmp != 0) return expCmp;
    } else if (expA != null && expB == null) {
      return -1;
    } else if (expA == null && expB != null) {
      return 1;
    }
    final dateCmp = a.dateArrived.compareTo(b.dateArrived);
    if (dateCmp != 0) return dateCmp;
    return a.batchId.compareTo(b.batchId);
  }

  /// Days remaining until batch expiration (null if no expiration date set).
  int? get daysUntilExpiration {
    if (expiryDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry =
        DateTime(expiryDate!.year, expiryDate!.month, expiryDate!.day);
    return expiry.difference(today).inDays;
  }

  /// Whether batch is already expired as of [DateTime.now].
  bool get isExpired => isExpiredAt(DateTime.now());

  /// Whether batch expires within the 30-day warning threshold (and is not yet expired).
  bool get isNearExpiration {
    if (isExpired) return false;
    final days = daysUntilExpiration;
    return days != null && days >= 0 && days <= 30;
  }

  /// Whether batch is healthy (> 30 days or no expiration).
  bool get isSafe {
    if (isExpired) return false;
    final days = daysUntilExpiration;
    return days == null || days > 30;
  }

  /// Factory constructor to parse map / Firestore data safely.
  factory ProductBatch.fromMap(dynamic m) {
    if (m is! Map) {
      return ProductBatch(
        batchId: '',
        productId: '',
        remainingQty: 0,
        initialQty: 0,
        costPrice: 0.0,
        dateArrived: DateTime.now(),
      );
    }
    final data = Map<String, dynamic>.from(m);

    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val != null) {
        final parsed = DateTime.tryParse(val.toString());
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    DateTime? parseNullableDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val != null) return DateTime.tryParse(val.toString());
      return null;
    }

    final id = data['batchId']?.toString() ?? data['id']?.toString() ?? '';
    final prodId = data['productId']?.toString() ?? '';
    final prodName = data['productName']?.toString() ?? '';
    final remQty = (data['remainingQty'] as num? ??
            data['quantityRemaining'] as num? ??
            data['quantity'] as num? ??
            0)
        .toInt();
    final initQty = (data['initialQty'] as num? ?? remQty).toInt();
    final cost =
        (data['costPrice'] as num? ?? data['unitCost'] as num? ?? 0).toDouble();
    final arrived = parseDate(
      data['dateArrived'] ?? data['dateReceived'] ?? data['createdAt'],
      DateTime.now(),
    );
    final purchased = parseDate(
      data['datePurchased'] ?? data['dateArrived'] ?? data['dateReceived'],
      arrived,
    );
    final expiry =
        parseNullableDate(data['expiryDate'] ?? data['expirationDate']);
    final invoice = data['invoiceNumber']?.toString();

    return ProductBatch(
      batchId: id,
      productId: prodId,
      productName: prodName,
      supplierId: data['supplierId']?.toString(),
      supplierName: data['supplierName']?.toString(),
      poId: data['poId']?.toString(),
      poNumber: data['poNumber']?.toString(),
      datePurchased: purchased,
      dateArrived: arrived,
      expiryDate: expiry,
      costPrice: cost,
      initialQty: initQty < remQty ? remQty : initQty,
      remainingQty: remQty < 0 ? 0 : remQty,
      status: data['status']?.toString(),
      invoiceNumber: invoice,
    );
  }

  /// Factory constructor for parsing Firestore [DocumentSnapshot].
  factory ProductBatch.fromFirestore(DocumentSnapshot doc) {
    final data = Map<String, dynamic>.from(
        doc.data() as Map<String, dynamic>? ?? const {});
    data['batchId'] ??= doc.id;
    return ProductBatch.fromMap(data);
  }

  /// Convert model to Map for Firestore persistence (writes both canonical
  /// FIFO subcollection fields and legacy aliases for zero breaking changes).
  Map<String, dynamic> toMap() => {
        'batchId': batchId,
        'id': batchId,
        'productId': productId,
        'productName': productName,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'poId': poId,
        'poNumber': poNumber,
        'datePurchased': Timestamp.fromDate(datePurchased),
        'dateArrived': Timestamp.fromDate(dateArrived),
        'dateReceived': Timestamp.fromDate(dateArrived),
        'createdAt': Timestamp.fromDate(dateArrived),
        'expiryDate':
            expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
        'expirationDate':
            expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
        'costPrice': costPrice,
        'unitCost': costPrice,
        'initialQty': initialQty,
        'remainingQty': remainingQty,
        'quantityRemaining': remainingQty,
        'quantity': remainingQty,
        'status': status,
        'invoiceNumber': invoiceNumber,
      };

  /// Alias for [toMap] with server timestamp for subcollection writes.
  Map<String, dynamic> toFirestore() => {
        ...toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Create a copy with updated properties.
  ProductBatch copyWith({
    String? batchId,
    String? id,
    String? productId,
    String? productName,
    String? supplierId,
    String? supplierName,
    String? poId,
    String? poNumber,
    DateTime? datePurchased,
    DateTime? dateArrived,
    DateTime? dateReceived,
    DateTime? createdAt,
    DateTime? expiryDate,
    DateTime? expirationDate,
    double? costPrice,
    double? unitCost,
    int? initialQty,
    int? remainingQty,
    int? quantityRemaining,
    int? quantity,
    String? status,
    String? invoiceNumber,
  }) {
    final int nextRemaining =
        remainingQty ?? quantityRemaining ?? quantity ?? this.remainingQty;
    final String nextStatus = status ??
        (this.status == BatchStatus.archived
            ? BatchStatus.archived
            : (nextRemaining <= 0
                ? BatchStatus.depleted
                : (this.status == BatchStatus.expired
                    ? BatchStatus.expired
                    : BatchStatus.active)));

    return ProductBatch(
      batchId: batchId ?? id ?? this.batchId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      poId: poId ?? this.poId,
      poNumber: poNumber ?? this.poNumber,
      datePurchased: datePurchased ?? this.datePurchased,
      dateArrived: dateArrived ?? dateReceived ?? createdAt ?? this.dateArrived,
      expiryDate: expiryDate ?? expirationDate ?? this.expiryDate,
      costPrice: costPrice ?? unitCost ?? this.costPrice,
      initialQty: initialQty ?? this.initialQty,
      remainingQty: nextRemaining,
      status: nextStatus,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
    );
  }
}
