import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/todo.dart';
import 'package:todonote/utils/todo_trigger_candidates.dart';

void main() {
  final anchor = DateTime(2026, 6, 11);

  Todo todo({
    required String id,
    required String title,
    DateTime? scheduledDate,
    String? recurrenceType,
    String? recurrenceTemplateId,
    TodoStatus status = TodoStatus.open,
  }) {
    return Todo(
      id: id,
      title: title,
      status: status,
      scheduledDate: scheduledDate,
      recurrenceType: recurrenceType,
      recurrenceTemplateId: recurrenceTemplateId,
      createdAt: DateTime.utc(2026, 6, 1),
      updatedAt: DateTime.utc(2026, 6, 1),
    );
  }

  test('keeps only nearest candidate per recurring series', () {
    final candidates = filterTodoTriggerCandidates([
      todo(id: 'template', title: 'Checklist morning', recurrenceType: 'daily'),
      todo(
        id: 'instance-tomorrow',
        title: 'Checklist morning',
        scheduledDate: DateTime(2026, 6, 12),
        recurrenceTemplateId: 'template',
      ),
      todo(
        id: 'instance-next-week',
        title: 'Checklist morning',
        scheduledDate: DateTime(2026, 6, 18),
        recurrenceTemplateId: 'template',
      ),
      todo(
        id: 'normal',
        title: 'Normal todo',
        scheduledDate: DateTime(2026, 6, 13),
      ),
    ], anchor: anchor);

    expect(candidates.map((todo) => todo.id), ['instance-tomorrow', 'normal']);
  });

  test('excludes current todo and done candidates', () {
    final candidates = filterTodoTriggerCandidates(
      [
        todo(id: 'self', title: 'Self'),
        todo(id: 'done', title: 'Done', status: TodoStatus.done),
        todo(id: 'open', title: 'Open'),
      ],
      excludeId: 'self',
      anchor: anchor,
    );

    expect(candidates.map((todo) => todo.id), ['open']);
  });
}
