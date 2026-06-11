import '../utils/json_utils.dart';

enum RunStatus {
  inProgress,
  completed,
  abandoned;

  String get label {
    switch (this) {
      case RunStatus.inProgress:
        return 'Đang chạy';
      case RunStatus.completed:
        return 'Hoàn thành';
      case RunStatus.abandoned:
        return 'Đã hủy';
    }
  }

  String get backendValue {
    switch (this) {
      case RunStatus.inProgress:
        return 'in_progress';
      case RunStatus.completed:
        return 'completed';
      case RunStatus.abandoned:
        return 'abandoned';
    }
  }

  static RunStatus parse(String s) {
    switch (s) {
      case 'completed':
        return RunStatus.completed;
      case 'abandoned':
        return RunStatus.abandoned;
      default:
        return RunStatus.inProgress;
    }
  }
}

class Run {
  final String id;
  final String templateId;

  /// Custom name given when the run was started (optional).
  final String? name;

  /// Template title embedded by the server in list/detail responses.
  final String? templateTitle;
  final RunStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;

  const Run({
    required this.id,
    required this.templateId,
    this.name,
    this.templateTitle,
    this.status = RunStatus.inProgress,
    required this.startedAt,
    this.completedAt,
  });

  factory Run.fromJson(Map<String, dynamic> json) {
    return Run(
      id: json['id'] as String,
      templateId: json['template_id'] as String,
      name: json['name'] as String?,
      templateTitle: json['template_title'] as String?,
      status: RunStatus.parse(json['status'] as String? ?? 'in_progress'),
      startedAt: jsonDate(json['started_at'] as String),
      completedAt: jsonDateNullable(json['completed_at'] as String?),
    );
  }

  /// Best display name: custom run name → template title → fallback.
  String get displayName => name ?? templateTitle ?? 'Checklist';
}
