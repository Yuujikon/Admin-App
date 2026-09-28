import 'dart:async';
import 'package:flutter/material.dart';

/// A base class for all providers to handle shared state like loading
/// and stream subscription cleanup.
abstract class BaseProvider extends ChangeNotifier {
  final List<StreamSubscription> _subscriptions = [];
  bool _isLoading = false;
  bool _isDisposed = false;

  bool get isLoading => _isLoading;
  bool get isDisposed => _isDisposed;

  /// Sets the loading state and notifies listeners.
  @protected
  void setLoading(bool val) {
    if (_isDisposed) return;
    _isLoading = val;
    notifyListeners();
  }

  /// Registers a subscription to be cancelled when [dispose] is called.
  @protected
  void registerSubscription(StreamSubscription sub) {
    _subscriptions.add(sub);
  }

  /// Cancels all registered subscriptions.
  void cancelSubscriptions() {
    for (var s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
  }

  @override
  void dispose() {
    _isDisposed = true;
    cancelSubscriptions();
    super.dispose();
  }

  /// Safe way to notify listeners only if the provider hasn't been disposed.
  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }
}
