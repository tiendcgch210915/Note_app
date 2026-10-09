import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/checklists_repository.dart';
import '../models/run.dart';
import '../models/run_item.dart';
import 'active_session_lock.dart';
import 'checklist_local_events.dart';

/// Snapshot của một checklist đang được thực hiện (một run đang chạy).
class ChecklistSession {
  final String runId;
  final String templateId;
  final String title;

  /// Mốc bắt đầu của run (UTC). Thời gian đã trôi qua luôn tính từ mốc này nên
  /// khớp với đồng hồ trên màn hình run và với `duration_ms` khi hoàn tất.
  final DateTime startedAt;
  final Duration elapsed;

  /// Số bước đã xong / tổng số bước; `null` khi chưa biết.
  final int? doneSteps;
  final int? totalSteps;

  const ChecklistSession({
    required this.runId,
    required this.templateId,
    required this.title,
    required this.startedAt,
    required this.elapsed,
    this.doneSteps,
    this.totalSteps,
  });

  ChecklistSession copyWith({
    String? title,
    Duration? elapsed,
    int? doneSteps,
    int? totalSteps,
  }) {
    return ChecklistSession(
      runId: runId,
      templateId: templateId,
      title: title ?? this.title,
      startedAt: startedAt,
      elapsed: elapsed ?? this.elapsed,
      doneSteps: doneSteps ?? this.doneSteps,
      totalSteps: totalSteps ?? this.totalSteps,
    );
  }
}

typedef ChecklistLocalRunLoader =
    Future<({Run run, List<RunItem> items})?> Function(String id);

/// Giữ phiên "đang làm checklist" ở cấp app để đồng hồ đếm xuôi tiếp tục chạy
/// và banner toàn app còn hiện khi người dùng rời màn hình run. Chỉ lưu
/// in-memory (run vẫn nằm trong Drift/sync như trước): tắt hẳn app thì phiên
/// mất, run vẫn ở trạng thái "Đang chạy" trong lịch sử.
///
/// Đồng hồ luôn tính từ `startedAt` của run theo wall-clock, không đếm cộng dồn
/// từng tick nên không lệch khi app ở nền. Mỗi lúc dữ liệu cục bộ đổi (kể cả
/// sync pull) controller đọc lại run từ Drift: run bị xóa/hoàn thành/hủy ở nơi
/// khác thì phiên tự kết thúc.
///
/// Chỉ một phiên tại một thời điểm, và dùng chung khóa với todo
/// ([ActiveSessionLock]).
class ChecklistSessionController {
  ChecklistSessionController._();

  static final ChecklistSessionController instance =
      ChecklistSessionController._();

  final ValueNotifier<ChecklistSession?> session =
      ValueNotifier<ChecklistSession?>(null);

  /// Các run đang có màn hình chi tiết nằm trên stack — banner ẩn đi nếu
  /// trong đó có run của phiên (màn hình đã có đồng hồ riêng).
  final ValueNotifier<Set<String>> openRunScreens = ValueNotifier<Set<String>>(
    const {},
  );

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  @visibleForTesting
  ChecklistLocalRunLoader localRunLoader = (id) =>
      ChecklistsRepository.instance.getRunLocal(id);

  Timer? _timer;
  int _refreshGeneration = 0;
  bool _listening = false;
  final Map<String, int> _openScreens = {};

  bool isActiveFor(String runId) => session.value?.runId == runId;

  /// Bắt đầu phiên cho [run]. Trả về `false` (không đổi gì) nếu đang có một
  /// phiên khác — checklist hay todo — chưa kết thúc, hoặc run không còn ở
  /// trạng thái "đang chạy". Gọi lại cho đúng run đang chạy là vô hại.
  ///
  /// [items] chỉ để hiện tiến độ ban đầu; thiếu thì banner chưa hiện số bước
  /// cho tới lần đọc lại Drift đầu tiên.
  bool start(Run run, {List<RunItem>? items}) {
    if (run.status != RunStatus.inProgress) return false;
    if (isActiveFor(run.id)) return true;
    if (!ActiveSessionLock.instance.tryAcquire(
      ActiveSessionRef(ActiveSessionKind.checklist, run.id),
    )) {
      return false;
    }
    _stopTimer();
    final startedAt = run.startedAt.toUtc();
    session.value = ChecklistSession(
      runId: run.id,
      templateId: run.templateId,
      title: run.displayName,
      startedAt: startedAt,
      elapsed: _elapsedSince(startedAt),
      doneSteps: items == null ? null : _doneCount(items),
      totalSteps: items?.length,
    );
    _scheduleTick();
    if (!_listening) {
      _listening = true;
      ChecklistLocalEvents.instance.addListener(_onLocalChanged);
    }
    if (items == null) unawaited(refreshFromLocal());
    return true;
  }

  /// Thời gian đã trôi qua, làm tròn xuống giây nguyên (đồng hồ chỉ hiện giây).
  Duration _elapsedSince(DateTime startedAt) {
    final elapsed = clock().toUtc().difference(startedAt);
    if (elapsed.isNegative) return Duration.zero;
    return Duration(seconds: elapsed.inSeconds);
  }

  int _doneCount(List<RunItem> items) =>
      items.where((item) => item.status == RunItemStatus.done).length;

  /// Hẹn tick kế tiếp đúng lúc số giây của đồng hồ nhảy, thay vì cứ 1 giây một
  /// lần: timer định kỳ trôi dần so với mốc `startedAt` nên thỉnh thoảng sẽ
  /// nhảy cóc một giây.
  void _scheduleTick() {
    _timer?.cancel();
    final current = session.value;
    if (current == null) return;
    final elapsedMs = clock()
        .toUtc()
        .difference(current.startedAt)
        .inMilliseconds;
    final intoSecond = elapsedMs < 0 ? 0 : elapsedMs % 1000;
    _timer = Timer(Duration(milliseconds: 1000 - intoSecond), _tick);
  }

  void _tick() {
    final current = session.value;
    if (current == null) {
      _timer = null;
      return;
    }
    session.value = current.copyWith(elapsed: _elapsedSince(current.startedAt));
    _scheduleTick();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Kết thúc phiên (run đã hoàn tất/hủy). Chỉ kết thúc khi [runId] khớp phiên
  /// đang chạy, để màn hình của một run khác không vô tình tắt phiên của run
  /// này. Trả về `true` nếu có phiên được kết thúc.
  bool finish({String? runId}) {
    final current = session.value;
    if (current == null) return false;
    if (runId != null && current.runId != runId) return false;
    _stopTimer();
    _refreshGeneration++;
    if (_listening) {
      _listening = false;
      ChecklistLocalEvents.instance.removeListener(_onLocalChanged);
    }
    session.value = null;
    ActiveSessionLock.instance.release(
      ActiveSessionRef(ActiveSessionKind.checklist, current.runId),
    );
    return true;
  }

  /// Hủy phiên không cần kết quả (logout, 401). Không đụng tới run trong Drift.
  void cancel() => finish();

  /// Hủy bỏ checklist đang làm: đánh dấu run "Đã hủy" (đồng bộ lên server) rồi
  /// kết thúc phiên. Lỗi từ repository được ném ra để caller báo người dùng và
  /// phiên được giữ nguyên.
  Future<void> abandonActive() async {
    final current = session.value;
    if (current == null) return;
    await ChecklistsRepository.instance.abandonRun(current.runId);
    finish(runId: current.runId);
    // Danh sách run đang mở phải đọc lại để không còn hiện "Đang chạy".
    ChecklistLocalEvents.instance.notifyChanged();
  }

  void _onLocalChanged() => unawaited(refreshFromLocal());

  /// Đối chiếu phiên với Drift: cập nhật tên + tiến độ, hoặc kết thúc phiên nếu
  /// run đã bị xóa/hoàn thành/hủy. Màn hình run gọi sau mỗi lần ghi bước.
  Future<void> refreshFromLocal() async {
    final started = session.value;
    if (started == null) return;
    final generation = ++_refreshGeneration;
    ({Run run, List<RunItem> items})? local;
    try {
      local = await localRunLoader(started.runId);
    } catch (_) {
      return;
    }
    final latest = session.value;
    if (latest == null || latest.runId != started.runId) return;
    if (generation != _refreshGeneration) return;
    if (local == null || local.run.status != RunStatus.inProgress) {
      cancel();
      return;
    }
    session.value = latest.copyWith(
      title: local.run.displayName,
      doneSteps: _doneCount(local.items),
      totalSteps: local.items.length,
    );
  }

  /// Ghi nhận một màn hình chi tiết của [runId] vừa được mở. Gọi từ
  /// `openRunDetail()` ngay trước khi push (không gọi trong `build`/`initState`
  /// vì sẽ báo cho banner `setState` giữa lúc dựng cây widget).
  void screenOpened(String runId) {
    _openScreens[runId] = (_openScreens[runId] ?? 0) + 1;
    _publishOpenScreens();
  }

  void screenClosed(String runId) {
    final count = _openScreens[runId];
    if (count == null) return;
    if (count <= 1) {
      _openScreens.remove(runId);
    } else {
      _openScreens[runId] = count - 1;
    }
    _publishOpenScreens();
  }

  void _publishOpenScreens() {
    final next = Set<String>.unmodifiable(_openScreens.keys);
    if (!setEquals(next, openRunScreens.value)) openRunScreens.value = next;
  }

  @visibleForTesting
  void resetForTest() {
    cancel();
    _openScreens.clear();
    openRunScreens.value = const {};
    clock = DateTime.now;
    localRunLoader = (id) => ChecklistsRepository.instance.getRunLocal(id);
  }
}
