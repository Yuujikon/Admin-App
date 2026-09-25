import 'dart:async';
import 'package:flutter/material.dart';
import '../models/expense.dart';
import '../services/firestore_service.dart';

class ExpenseProvider extends ChangeNotifier {
  final _fs = FirestoreService();
  final List<StreamSubscription> _subs = [];
  List<Expense> _expenses = [];

  List<Expense> get expenses => _expenses;

  Stream<List<Expense>> get expensesStream => _fs.expensesStream();

  void initialize() {
    cancelSubscriptions();
    _subs.add(_fs.expensesStream().listen((list) {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _expenses = list;
      notifyListeners();
    }, onError: (e) => debugPrint('Expenses Stream Error: $e')));
  }

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

  Future<void> addExpense(String description, double amount, String category) {
    final expense = Expense(
      id:          '',
      description: description,
      amount:      amount,
      category:    category,
      createdAt:   DateTime.now(),
    );
    return _fs.addExpense(expense);
    // Stream updates _expenses automatically
  }
}