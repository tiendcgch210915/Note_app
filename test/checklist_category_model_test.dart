import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/checklist_category.dart';
import 'package:todonote/models/template.dart';

void main() {
  test('checklist category parses REST numeric is_system', () {
    final category = ChecklistCategory.fromJson({
      'id': 'cat-1',
      'user_id': 'user-1',
      'name': 'Code',
      'slug': 'code',
      'icon': 'code',
      'color': '#3366ff',
      'sort_order': 10,
      'is_system': 1,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
      'deleted_at': null,
    });

    expect(category.name, 'Code');
    expect(category.isSystem, isTrue);
    expect(category.sortOrder, 10);
  });

  test('checklist category parses sync boolean is_system', () {
    final category = ChecklistCategory.fromJson({
      'id': 'cat-2',
      'user_id': 'user-1',
      'name': 'Work',
      'slug': 'work',
      'icon': null,
      'color': '#4f46e5',
      'sort_order': 0,
      'is_system': false,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
      'deleted_at': null,
    });

    expect(category.isSystem, isFalse);
    expect(category.icon, isNull);
  });

  test('template parses category_id with legacy category fallback', () {
    final template = Template.fromJson({
      'id': 'tpl-1',
      'title': 'Review',
      'description': null,
      'icon': 'code',
      'category': 'Code',
      'category_id': 'cat-1',
      'sort_order': 12,
      'is_system': 0,
      'times_used': 2,
      'last_used_at': null,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    });

    expect(template.categoryId, 'cat-1');
    expect(template.category, 'Code');
    expect(template.sortOrder, 12);
    expect(template.isSystem, isFalse);
  });
}
