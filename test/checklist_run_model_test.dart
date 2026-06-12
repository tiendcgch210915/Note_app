import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/run.dart';

void main() {
  test('Run parses nullable duration_ms as integer milliseconds', () {
    final run = Run.fromJson({
      'id': 'run-1',
      'template_id': 'template-1',
      'name': 'Morning',
      'status': 'completed',
      'started_at': '2026-06-12T08:00:00.000Z',
      'completed_at': '2026-06-12T08:01:30.000Z',
      'duration_ms': 90000,
    });

    expect(run.durationMs, 90000);
    expect(run.status, RunStatus.completed);
  });

  test('Run falls back to null duration for missing or invalid values', () {
    final missing = Run.fromJson({
      'id': 'run-1',
      'template_id': 'template-1',
      'started_at': '2026-06-12T08:00:00.000Z',
    });
    final invalid = Run.fromJson({
      'id': 'run-2',
      'template_id': 'template-1',
      'started_at': '2026-06-12T08:00:00.000Z',
      'duration_ms': '90000',
    });

    expect(missing.durationMs, isNull);
    expect(invalid.durationMs, isNull);
  });
}
