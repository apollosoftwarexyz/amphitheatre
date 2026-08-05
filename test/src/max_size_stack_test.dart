import 'package:amphitheatre/src/max_size_stack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MaxSizeStack', () {

    test('can be constructed with a valid size', () {
      expect(() => MaxSizeStack<int>(1), returnsNormally);
      expect(MaxSizeStack<int>(1).size, equals(1));

      expect(() => MaxSizeStack<int>(32), returnsNormally);
      expect(MaxSizeStack<int>(32).size, equals(32));
    });

    test('cannot be constructed with an invalid size', () {
      expect(() => MaxSizeStack<int>(0), throwsArgumentError);
      expect(() => MaxSizeStack<int>(-1), throwsArgumentError);
    });

    test('initially returns true for isEmpty and false for isNotEmpty', () {
      final stack = MaxSizeStack<int>(1);
      expect(stack.isEmpty, isTrue);
      expect(stack.isNotEmpty, isFalse);
    });

    test('returns false for isEmpty and true for isNotEmpty when items are on the stack', () {
      final stack = MaxSizeStack<int>(1)..push(0);
      expect(stack.isEmpty, isFalse);
      expect(stack.isNotEmpty, isTrue);
    });

    test('is empty (with zero length) upon initialization', () {
      final stack = MaxSizeStack<int>(1);
      expect(stack.isFull, isFalse);
      expect(stack.isNotFull, isTrue);
      expect(stack.length, equals(0));
    });

    test('is full (with length = size) once the max size number of elements have been added', () {
      final stack = MaxSizeStack<int>(1)..push(0);
      expect(stack.isFull, isTrue);
      expect(stack.isNotFull, isFalse);
      expect(stack.length, equals(1));
    });

    test('returns (and removes) the last pushed element when pop is called', () {
      final stack = MaxSizeStack<int>(1)..push(0);
      expect(stack.length, equals(1));
      expect(stack.isFull, isTrue);
      expect(stack.isEmpty, isFalse);
      expect(stack.pop(), equals(0));
      expect(stack.isFull, isFalse);
      expect(stack.isEmpty, isTrue);
    });
    
    group('returns (without removing) the last pushed element when peek is called', () {
      test('for size of 1', () {
        final stack = MaxSizeStack<int>(1)..push(0);
        expect(stack.isFull, isTrue);
        expect(stack.isEmpty, isFalse);
        expect(stack.length, equals(1));
        expect(stack.peek(), equals(0));
        expect(stack.length, equals(1));
        expect(stack.peek(), equals(0));
        expect(stack.length, equals(1));
        expect(stack.isFull, isTrue);
        expect(stack.isEmpty, isFalse);
      });

      test('for size of 2', () {
        final stack = MaxSizeStack<int>(2)..push(0)..push(1);
        expect(stack.isFull, isTrue);
        expect(stack.isEmpty, isFalse);
        expect(stack.length, equals(2));
        expect(stack.peek(), equals(1));
        expect(stack.length, equals(2));
        expect(stack.peek(), equals(1));
        expect(stack.length, equals(2));
        expect(stack.isFull, isTrue);
        expect(stack.isEmpty, isFalse);
      });
    });

    group('drops the oldest element if a new element would cause the size to be exceeded', () {
      test('for size of 1', () {
        final stack = MaxSizeStack<int>(1)..push(0)..push(1);
        expect(stack.isFull, isTrue);
        expect(stack.isEmpty, isFalse);
        expect(stack.length, equals(1));
        expect(stack.pop(), equals(1));
        expect(stack.length, equals(0));
        expect(stack.isFull, isFalse);
        expect(stack.isEmpty, isTrue);
      });

      test('for size of 2', () {
        final stack = MaxSizeStack<int>(2)..push(0)..push(1)..push(2);
        expect(stack.isFull, isTrue);
        expect(stack.isEmpty, isFalse);
        expect(stack.length, equals(2));
        expect(stack.pop(), equals(2));
        expect(stack.length, equals(1));
        expect(stack.pop(), equals(1));
        expect(stack.length, equals(0));
        expect(stack.isFull, isFalse);
        expect(stack.isEmpty, isTrue);
      });
    });

    test('clear removes all elements', () {
      final stack = MaxSizeStack<int>(2)..push(0)..push(1)..push(2);
      expect(stack.isFull, isTrue);
      expect(stack.isEmpty, isFalse);
      expect(stack.length, equals(2));

      stack.clear();

      expect(stack.isFull, isFalse);
      expect(stack.isEmpty, isTrue);
      expect(stack.length, equals(0));
    });
  });
}
