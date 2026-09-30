import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/shift_session.dart';
import 'base_provider.dart';

class ShiftProvider extends BaseProvider {
  final _db = FirebaseFirestore.instance;
  CollectionReference get _shifts => _db.collection('shifts');

  ShiftSession? _currentShift;
  ShiftSession? get currentShift => _currentShift;
  bool get hasActiveShift => _currentShift != null && _currentShift!.status == ShiftStatus.active;

  List<ShiftSession> _pastShifts = [];
  List<ShiftSession> get pastShifts => _pastShifts;

  ShiftProvider() {
    _initShiftListener();
  }

  void _initShiftListener() {
    registerSubscription(_shifts
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen((snap) {
      if (snap.docs.isNotEmpty) {
        _currentShift = ShiftSession.fromFirestore(snap.docs.first);
      } else {
        _currentShift = null;
      }
      notifyListeners();
    }, onError: (e) => debugPrint('ShiftListener Error: $e')));

    registerSubscription(_shifts
        .where('status', isEqualTo: 'closed')
        .orderBy('closedAt', descending: true)
        .limit(20)
        .snapshots()
        .listen((snap) {
      _pastShifts = snap.docs.map((doc) => ShiftSession.fromFirestore(doc)).toList();
      notifyListeners();
    }, onError: (e) => debugPrint('PastShifts Error: $e')));
  }

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

    final updatedDrops = [..._currentShift!.cashDrops, drop];
    final updated = _currentShift!.copyWith(cashDrops: updatedDrops);

    await _shifts.doc(_currentShift!.id).update({
      'cashDrops': updatedDrops.map((d) => d.toMap()).toList(),
    });

    _currentShift = updated;
    notifyListeners();
  }

  Future<void> updateShiftSales({required double cashAmount, required double gcashAmount}) async {
    if (_currentShift == null) return;

    final updatedCashSales = _currentShift!.cashSales + cashAmount;
    final updatedGcashSales = _currentShift!.gcashSales + gcashAmount;

    await _shifts.doc(_currentShift!.id).update({
      'cashSales': updatedCashSales,
      'gcashSales': updatedGcashSales,
    });

    _currentShift = _currentShift!.copyWith(
      cashSales: updatedCashSales,
      gcashSales: updatedGcashSales,
    );
    notifyListeners();
  }

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
