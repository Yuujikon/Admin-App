import 'dart:async';
import 'package:flutter/material.dart';
import '../models/expense.dart';
import '../services/firestore_service.dart';

/// Provider for managing operational expenses data streams and persistence.
class ExpenseProvider extends ChangeNotifier {
  final _fs = FirestoreService();
  final List<StreamSubscription> _subs = [];
  List<Expense> _expenses = [];

  /// Returns list of recorded expenses ordered by date descending.
  List<Expense> get expenses => _expenses;

  /// Returns continuous stream of expenses from Firestore.
  Stream<List<Expense>> get expensesStream => _fs.expensesStream();

  /// Initializes real-time Firestore stream listener for store expenses.
  void initialize() {
    cancelSubscriptions();
    _subs.add(_fs.expensesStream().listen((list) {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _expenses = list;
      notifyListeners();
    }, onError: (e) => debugPrint('Expenses Stream Error: $e')));
  }

  /// Cancels all active Firestore stream subscriptions.
  void cancelSubscriptions() {
    for (var s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  @override
  void dispose() {
    cancelSubscriptions();
    super.dispose();
  }

  /// Adds a new operational expense record.
  Future<void> addExpense(String description, double amount, String category) {
    final expense = Expense(
      id: '',
      description: description,
      amount: amount,
      category: category,
      createdAt: DateTime.now(),
    );
    return _fs.addExpense(expense);
  }
}
