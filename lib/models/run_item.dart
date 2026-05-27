import '../utils/json_utils.dart';

enum RunItemStatus {
  pending,
  done,
  skipped;

  String get label {
    switch (this) {
      case RunItemStatus.pending:
        return 'Chưa làm';
      case RunItemStatus.done:
        return 'Hoàn thành';
      case RunItemStatus.skipped:
        return 'Bỏ qua';
    }
  }

  String get backendValue => name;

  static RunItemStatus parse(String s) {
    switch (s) {
      case 'done':
        return RunItemStatus.done;
      case 'skipped':
        return RunItemStatus.skipped;
      default:
        return RunItemStatus.pending;
    }
  }
}

class RunItem {
  final String id;
  final String runId;
  final String templateItemId;
  final RunItemStatus status;
  final String title; // snapshot từ template_item (JOIN)
  final String? description;
  final bool isRequired;
  final int position;
  final DateTime? completedAt;
  final String? note;

  const RunItem({
    required this.id,
    required this.runId,
    required this.templateItemId,
    this.status = RunItemStatus.pending,
    required this.title,
    this.description,
    this.isRequired = true,
    required this.position,
    this.completedAt,
    this.note,
  });

  factory RunItem.fromJson(Map<String, dynamic> json) {
    return RunItem(
      id: json['id'] as String,
      runId: json['run_id'] as String,
      templateItemId: json['template_item_id'] as String,
      status: RunItemStatus.parse(json['status'] as String? ?? 'pending'),
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      isRequired: jsonBool(json['is_required'], fallback: true),
      position: (json['position'] as num?)?.toInt() ?? 0,
      completedAt: jsonDateNullable(json['completed_at'] as String?),
      note: json['note'] as String?,
    );
  }

  RunItem copyWith({RunItemStatus? status, DateTime? completedAt, String? note}) {
    return RunItem(
      id: id,
      runId: runId,
      templateItemId: templateItemId,
      status: status ?? this.status,
      title: title,
      description: description,
      isRequired: isRequired,
      position: position,
      completedAt: completedAt ?? this.completedAt,
      note: note ?? this.note,
    );
  }
}
