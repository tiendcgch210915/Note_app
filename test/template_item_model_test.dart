import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/models/template_item.dart';

void main() {
  test('TemplateItem copyWith updates only provided fields', () {
    const item = TemplateItem(
      id: 'item-1',
      templateId: 'template-1',
      position: 1,
      title: 'Bước cũ',
      description: 'Ghi chú',
      isRequired: true,
    );

    final updated = item.copyWith(title: 'Bước mới');

    expect(updated.id, item.id);
    expect(updated.templateId, item.templateId);
    expect(updated.position, item.position);
    expect(updated.title, 'Bước mới');
    expect(updated.description, item.description);
    expect(updated.isRequired, isTrue);
  });
}
