import 'package:amphitheatre/amphitheatre.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AmphitheatreEditorOptions.shouldAutoAccept', () {
    const options = AmphitheatreEditorOptions(
      canAutoAccept: true,
      minLength: Duration(seconds: 10),
    );

    test('accepts a video shorter than minLength', () {
      expect(options.shouldAutoAccept(const Duration(seconds: 9)), isTrue);
    });

    test('accepts a video exactly minLength long: nothing to trim', () {
      expect(options.shouldAutoAccept(const Duration(seconds: 10)), isTrue);
    });

    test('does not accept a video longer than minLength', () {
      expect(
        options.shouldAutoAccept(const Duration(seconds: 10, milliseconds: 1)),
        isFalse,
      );
    });

    test('accepts a zero-length video when minLength is zero', () {
      const zero = AmphitheatreEditorOptions(
        canAutoAccept: true,
        minLength: Duration.zero,
      );
      expect(zero.shouldAutoAccept(Duration.zero), isTrue);
      expect(zero.shouldAutoAccept(const Duration(seconds: 1)), isFalse);
    });

    test('never accepts without canAutoAccept', () {
      const optOut = AmphitheatreEditorOptions(
        minLength: Duration(seconds: 10),
      );
      expect(optOut.shouldAutoAccept(const Duration(seconds: 5)), isFalse);
      expect(optOut.shouldAutoAccept(const Duration(seconds: 10)), isFalse);
    });
  });
}
