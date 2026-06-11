import 'package:flutter/foundation.dart';

enum SyncState { idle, syncing, pendingChanges, error }

class SyncStatus {
  final SyncState state;
  final int pendingCount;
  final String? errorMessage;

  const SyncStatus({
    this.state = SyncState.idle,
    this.pendingCount = 0,
    this.errorMessage,
  });

  SyncStatus copyWith({
    SyncState? state,
    int? pendingCount,
    String? errorMessage,
  }) {
    return SyncStatus(
      state: state ?? this.state,
      pendingCount: pendingCount ?? this.pendingCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  String toString() =>
      'SyncStatus(state: $state, pending: $pendingCount, error: $errorMessage)';
}

/// Global ValueNotifier for sync state. Widgets can listen to this to show
/// the sync indicator (idle / syncing / N changes pending).
class SyncStatusNotifier extends ValueNotifier<SyncStatus> {
  SyncStatusNotifier._() : super(const SyncStatus());

  static final SyncStatusNotifier instance = SyncStatusNotifier._();

  void beginSync() {
    value = value.copyWith(state: SyncState.syncing, errorMessage: null);
  }

  void endSync({int pendingCount = 0, String? error}) {
    if (error != null) {
      value = value.copyWith(state: SyncState.error, errorMessage: error);
    } else if (pendingCount > 0) {
      value = value.copyWith(
        state: SyncState.pendingChanges,
        pendingCount: pendingCount,
      );
    } else {
      value = value.copyWith(
        state: SyncState.idle,
        pendingCount: 0,
        errorMessage: null,
      );
    }
  }

  void setPendingCount(int count) {
    if (value.state != SyncState.syncing) {
      value = value.copyWith(
        state: count > 0 ? SyncState.pendingChanges : SyncState.idle,
        pendingCount: count,
      );
    }
  }
}
