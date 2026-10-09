import 'package:flutter_test/flutter_test.dart';
import 'package:todonote/push/push_target.dart';

void main() {
  group('PushTarget.fromData', () {
    test('reads type and id', () {
      final target = PushTarget.fromData({'type': 'todo', 'id': 'abc'});

      expect(target, const PushTarget(type: 'todo', id: 'abc'));
    });

    test('id is optional', () {
      expect(
        PushTarget.fromData({'type': 'example'}),
        const PushTarget(type: 'example'),
      );
    });

    test('normalises type to lower case and trims values', () {
      expect(
        PushTarget.fromData({'type': '  Todo ', 'id': ' 42 '}),
        const PushTarget(type: 'todo', id: '42'),
      );
    });

    test('accepts non-string values from FCM data', () {
      expect(
        PushTarget.fromData({'type': 'todo', 'id': 7}),
        const PushTarget(type: 'todo', id: '7'),
      );
    });

    test('blank id is treated as missing', () {
      expect(
        PushTarget.fromData({'type': 'todo', 'id': '  '}),
        const PushTarget(type: 'todo'),
      );
    });

    test('returns null without a usable type', () {
      expect(PushTarget.fromData(null), isNull);
      expect(PushTarget.fromData({}), isNull);
      expect(PushTarget.fromData({'id': 'abc'}), isNull);
      expect(PushTarget.fromData({'type': ''}), isNull);
    });
  });

  group('payload round trip', () {
    test('survives toPayload → fromPayload', () {
      const target = PushTarget(type: 'note', id: 'n-1');

      expect(PushTarget.fromPayload(target.toPayload()), target);
    });

    test('target without id round-trips', () {
      const target = PushTarget(type: 'example');

      expect(PushTarget.fromPayload(target.toPayload()), target);
    });

    test('garbage payloads give null instead of throwing', () {
      expect(PushTarget.fromPayload(null), isNull);
      expect(PushTarget.fromPayload(''), isNull);
      expect(PushTarget.fromPayload('not json'), isNull);
      expect(PushTarget.fromPayload('[1,2,3]'), isNull);
      expect(PushTarget.fromPayload('"todo"'), isNull);
      expect(PushTarget.fromPayload('{"id":"x"}'), isNull);
    });
  });
}
