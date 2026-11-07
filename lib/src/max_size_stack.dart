import 'dart:collection';

/// A stack that has a maximum number of entries. When more entries are written
/// than the size of the stack permits, the oldest entries are dropped.
/// 
/// This is a LIFO data structure; the last element [push]ed onto the stack
/// will be the first element [pop]ped from the stack.
class MaxSizeStack<E> {

  /// The size of the stack.
  final int size;

  /// The underlying queue of values.
  final Queue<E> _values = Queue();

  /// The number of elements in this stack.  
  int get length => _values.length;

  /// Whether this collection has no elements.
  bool get isEmpty => _values.isEmpty;

  /// Whether this collection has at least one element.
  bool get isNotEmpty => _values.isNotEmpty;

  /// Whether this collection is full (i.e., it has [size] elements).
  bool get isFull => _values.length == size;

  /// Whether this collection is not full (i.e., it does not have [size] elements).
  bool get isNotFull => _values.length != size;

  /// Construct a [MaxSizeStack] of the given max [size].
  MaxSizeStack(this.size) {
    if (size < 1) {
      throw ArgumentError.value(size, 'size', 'The size must be greater than zero.');
    }
  }

  /// Peek the first element on the stack.
  /// 
  /// The stack must not be empty.
  E peek() => _values.first;

  /// Push the given [element] onto the stack.
  /// 
  /// If the stack would be larger than the [size] after the element is pushed,
  /// the oldest element in the stack is dropped.
  void push(E element) {
    if (_values.length + 1 > size) {
      _values.removeLast();
    }

    _values.addFirst(element);
  }

  /// Pops the most recently added element off the stack.
  /// 
  /// The stack must not be empty.
  E pop() => _values.removeFirst();

  /// Remove all elements in the stack.
  void clear() => _values.clear();
  
}
