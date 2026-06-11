import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'sync_worker.dart';

/// Listens to network connectivity changes and triggers [SyncWorker.sync()]
/// automatically when the device reconnects.
///
/// Also provides a write-triggered sync with a 2-second debounce:
///   ConnectivitySync.instance.scheduleWriteSync()
class ConnectivitySync {
  ConnectivitySync._();
  static final ConnectivitySync instance = ConnectivitySync._();

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _debounce;
  bool _wasOffline = false;

  /// Call once at app startup (after auth init).
  Future<void> init() async {
    // Check initial connectivity
    final initial = await Connectivity().checkConnectivity();
    _wasOffline = _isOffline(initial);

    // Subscribe to changes
    _sub = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _debounce?.cancel();
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final offline = _isOffline(results);
    if (_wasOffline && !offline) {
      // Was offline, now online → sync immediately
      debugPrint('[ConnectivitySync] Reconnected → triggering sync');
      SyncWorker.instance.sync();
    }
    _wasOffline = offline;
  }

  static bool _isOffline(List<ConnectivityResult> results) {
    return results.every((r) => r == ConnectivityResult.none);
  }

  /// Call after any local write to schedule a sync in 2 seconds.
  /// Repeated calls within the 2s window are coalesced into a single sync.
  void scheduleWriteSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      debugPrint('[ConnectivitySync] Write debounce fired → triggering sync');
      SyncWorker.instance.sync();
    });
  }

  /// Cancel any pending debounced sync.
  void cancelPending() {
    _debounce?.cancel();
  }
}
