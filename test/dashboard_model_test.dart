import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/dashboard.dart';
import 'package:todonote/utils/quadrant_utils.dart';

void main() {
  test(
    'today snapshot parses fixed q1-q4 counts and ignores extra buckets',
    () {
      final snapshot = DashboardSnapshot.fromJson({
        'date': '2026-06-10',
        'score': 80,
        'todos': {'total': 4, 'done': 1},
        'eisenhower_counts': {'q1': 1, 'q4': 2, 'unclassified': 99},
        'habits_today': {'total': 2, 'completed': 1},
      });

      expect(snapshot.date, DateTime(2026, 6, 10));
      expect(
        snapshot.eisenhowerCounts.keys,
        orderedEquals(dashboardQuadrantKeys),
      );
      expect(snapshot.eisenhowerCounts, {'q1': 1, 'q2': 0, 'q3': 0, 'q4': 2});
      expect(snapshot.eisenhowerCounts.containsKey('unclassified'), isFalse);
    },
  );

  test('today snapshot tolerates missing fields', () {
    final snapshot = DashboardSnapshot.fromJson({});

    expect(snapshot.score, 0);
    expect(snapshot.todosTotal, 0);
    expect(snapshot.todosDone, 0);
    expect(snapshot.habitsTotal, 0);
    expect(snapshot.habitsCompleted, 0);
    expect(snapshot.eisenhowerCounts, {'q1': 0, 'q2': 0, 'q3': 0, 'q4': 0});
  });

  test('eisenhower detail parses DTOs from fixed quadrants only', () {
    final detail = EisenhowerDetail.fromJson({
      'date': '2026-06-10',
      'counts': {'q1': 1, 'q2': 1, 'q3': 1, 'q4': 1, 'extra': 100},
      'by_quadrant': {
        'q1': [
          {
            'id': 'todo-q1',
            'title': 'Q1',
            'status': 'open',
            'scheduled_date': '2026-06-10',
            'is_important': true,
            'is_urgent': true,
            'is_frog': false,
            'frog_date': null,
            'quadrant': 'q1',
            'tags': [
              {
                'id': 'tag-1',
                'name': 'Work',
                'color': '#3366ff',
                'created_at': '2026-06-10T00:00:00.000Z',
                'updated_at': '2026-06-10T00:00:00.000Z',
              },
            ],
            'tag_ids': ['tag-1'],
          },
        ],
        'q2': [
          {
            'id': 'todo-done',
            'title': 'Done',
            'status': 'done',
            'is_important': true,
            'is_urgent': false,
            'is_frog': false,
            'quadrant': 'q2',
          },
        ],
        'q3': [
          {
            'id': 'todo-q3',
            'title': 'Q3',
            'status': 'open',
            'is_important': false,
            'is_urgent': true,
            'is_frog': false,
          },
        ],
        'q4': [
          {
            'id': 'legacy-unclassified',
            'title': 'Legacy',
            'status': 'open',
            'is_frog': false,
          },
        ],
        'unclassified': [
          {'id': 'ignored', 'title': 'Ignored', 'status': 'open'},
        ],
      },
    });

    expect(detail.counts.keys, orderedEquals(dashboardQuadrantKeys));
    expect(detail.byQuadrant.keys, orderedEquals(dashboardQuadrantKeys));
    expect(detail.byQuadrant['q1']!.single.id, 'todo-q1');
    expect(detail.byQuadrant['q1']!.single.tags.single.name, 'Work');
    expect(detail.byQuadrant['q1']!.single.tagIds, ['tag-1']);
    expect(detail.byQuadrant['q2'], isEmpty);
    expect(detail.byQuadrant['q3']!.single.quadrant, 'q3');
    expect(detail.byQuadrant['q4']!.single.id, 'legacy-unclassified');
    expect(detail.byQuadrant['q4']!.single.quadrant, 'q4');
    expect(detail.byQuadrant.containsKey('unclassified'), isFalse);
  });

  test('unclassified or null important urgent maps to q4 locally', () {
    final todo = DashboardEisenhowerTodo.fromJson({
      'id': 'legacy',
      'title': 'Legacy',
      'status': 'open',
      'quadrant': 'unclassified',
    }, fallbackQuadrant: 'unknown');

    expect(todo.isImportant, isFalse);
    expect(todo.isUrgent, isFalse);
    expect(todo.quadrant, 'q4');
    expect(QuadrantUtils.from(), Quadrant.q4);
  });
}
