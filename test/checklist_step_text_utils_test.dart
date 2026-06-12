import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/utils/checklist_step_text_utils.dart';

void main() {
  test('parseChecklistStepLines splits lines and strips list markers', () {
    final steps = parseChecklistStepLines('''
- Ăn
* Uống
1. Mặc quần áo & đi chơi
[ ] Rút tiền
• Chuẩn bị ví
''');

    expect(steps, [
      'Ăn',
      'Uống',
      'Mặc quần áo & đi chơi',
      'Rút tiền',
      'Chuẩn bị ví',
    ]);
  });

  test('parseChecklistStepLines drops empty lines', () {
    final steps = parseChecklistStepLines('\n\nA\n\nB\n');

    expect(steps, ['A', 'B']);
  });
}
