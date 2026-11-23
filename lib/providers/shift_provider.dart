import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/shift_session.dart';
import 'base_provider.dart';

/// Provider for managing active cashier working shifts, cash drops, and Z-Reading drawer audits.
class ShiftProvider extends BaseProvider {
  final _db = FirebaseFirestore.instance;
  CollectionReference get _shifts => _db.collection('shifts');

  ShiftSession? _currentShift;

  /// Currently active shift session, or null if no shift is open.
  ShiftSession? get currentShift => _currentShift;

  /// True if a shift session is currently active.
  bool get hasActiveShift =>
      _currentShift != null && _currentShift!.status == ShiftStatus.active;

  List<ShiftSession> _pastShifts = [];

  /// Historical list of closed shift sessions.
  List<ShiftSession> get pastShifts => _pastShifts;

  List<ShiftSession> _allShifts = [];

  /// Full historical list of all shift sessions (active & closed).
  List<ShiftSession> get allShifts => _allShifts;

  /// Creates ShiftProvider without starting Firestore streams before auth.
  ShiftProvider();

  /// Initializes or re-initializes real-time Firestore listeners for shift sessions after login.
  void initialize() {
    cancelSubscriptions();
    registerSubscription(_shifts.snapshots().listen((snap) {
      final list =
          snap.docs.map((doc) => ShiftSession.fromFirestore(doc)).toList();

      // Sort all shifts by openedAt date descending (newest first)
      list.sort((a, b) => b.openedAt.compareTo(a.openedAt));

      _allShifts = list;

      try {
        _currentShift = list.firstWhere((s) => s.status == ShiftStatus.active);
      } catch (_) {
        _currentShift = null;
      }

      _pastShifts = list.where((s) => s.status == ShiftStatus.closed).toList();

      notifyListeners();
    }, onError: (e) => debugPrint('Shifts Listener Error: $e')));
  }

  /// Opens a new cashier shift session with an initial cash drawer float.
  Future<void> openShift({
    required String cashierId,
    required String cashierName,
    required double openingFloat,
  }) async {
    final newShift = ShiftSession(
      id: const Uuid().v4(),
      cashierId: cashierId,
      cashierName: cashierName,
      openedAt: DateTime.now(),
      openingFloat: openingFloat,
      status: ShiftStatus.active,
    );

    await _shifts.doc(newShift.id).set(newShift.toFirestore());
    _currentShift = newShift;
    notifyListeners();
  }

  /// Records a mid-shift cash drop / withdrawal from register drawer atomically.
  Future<void> recordCashDrop({
    required double amount,
    required String reason,
  }) async {
    if (_currentShift == null) return;

    final drop = CashDrop(
      id: const Uuid().v4(),
      amount: amount,
      reason: reason,
      createdAt: DateTime.now(),
    );

    await _shifts.doc(_currentShift!.id).update({
      'cashDrops': FieldValue.arrayUnion([drop.toMap()]),
    });

    final updatedDrops = [..._currentShift!.cashDrops, drop];
    _currentShift = _currentShift!.copyWith(cashDrops: updatedDrops);
    notifyListeners();
  }

  /// Atomically increments cumulative shift sales, items sold, cash received, and change given.
  Future<void> updateShiftSales({
    required double cashAmount,
    required double gcashAmount,
    int itemsSold = 0,
    double cashReceived = 0.0,
    double changeGiven = 0.0,
  }) async {
    if (_currentShift == null) return;

    await _shifts.doc(_currentShift!.id).update({
      'cashSales': FieldValue.increment(cashAmount),
      'gcashSales': FieldValue.increment(gcashAmount),
      'itemsSoldCount': FieldValue.increment(itemsSold),
      'totalCashReceived': FieldValue.increment(cashReceived),
      'totalChangeGiven': FieldValue.increment(changeGiven),
      'transactionCount': FieldValue.increment(1),
    });

    _currentShift = _currentShift!.copyWith(
      cashSales: _currentShift!.cashSales + cashAmount,
      gcashSales: _currentShift!.gcashSales + gcashAmount,
      itemsSoldCount: _currentShift!.itemsSoldCount + itemsSold,
      totalCashReceived: _currentShift!.totalCashReceived + cashReceived,
      totalChangeGiven: _currentShift!.totalChangeGiven + changeGiven,
      transactionCount: _currentShift!.transactionCount + 1,
    );
    notifyListeners();
  }

  /// Closes the active shift session and records the physical drawer cash count.
  Future<ShiftSession> closeShift({required double actualCashCounted}) async {
    if (_currentShift == null) throw Exception('No active shift to close');

    final closedShift = _currentShift!.copyWith(
      actualCashCounted: actualCashCounted,
      closedAt: DateTime.now(),
      status: ShiftStatus.closed,
    );

    await _shifts.doc(closedShift.id).update(closedShift.toFirestore());
    final result = closedShift;
    _currentShift = null;
    notifyListeners();
    return result;
  }
}
