import 'package:amphitheatre/src/editor/amphitheatre_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AmphitheatreEditorController', () {

    test('initially has no modifications', () {
      final controller = AmphitheatreEditorController();
      expect(controller.hasModification, isFalse);
      expect(controller.hasUndo, isFalse);
      expect(controller.hasRedo, isFalse);
    });

    test('returns true for hasModification and hasUndo after a modification', () {
      final controller = AmphitheatreEditorController();
      expect(controller.hasModification, isFalse);
      expect(controller.hasUndo, isFalse);

      controller.crop(
        start: Duration.zero,
        end: const Duration(milliseconds: 200),
      );

      expect(controller.hasModification, isTrue);
      expect(controller.hasUndo, isTrue);
    });

    test('returns true for hasRedo after an undo', () {
      final controller = AmphitheatreEditorController();
      expect(controller.hasRedo, isFalse);

      controller.crop(
        start: Duration.zero,
        end: const Duration(milliseconds: 200),
      );
      expect(controller.hasRedo, isFalse);

      controller.undo();
      expect(controller.hasRedo, isTrue);
    });

    test('undo and redo work intuitively', () {
      final controller = AmphitheatreEditorController();
      expect(controller.hasUndo, isFalse);
      expect(controller.hasRedo, isFalse);

      controller
        ..crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 200),
        )
        ..crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 100),
        );

      expect(
        controller.value, equals(
          AmphitheatreEditorModifications(
            crop: AmphitheatreEditorActionCrop(
              start: Duration.zero,
              end: const Duration(milliseconds: 100),
            ),
          ),
        ),
      );

      controller.undo();

      expect(
        controller.value, equals(
          AmphitheatreEditorModifications(
            crop: AmphitheatreEditorActionCrop(
              start: Duration.zero,
              end: const Duration(milliseconds: 200),
            ),
          ),
        ),
      );

      controller.redo();

      expect(
        controller.value, equals(
          AmphitheatreEditorModifications(
            crop: AmphitheatreEditorActionCrop(
              start: Duration.zero,
              end: const Duration(milliseconds: 100),
            ),
          ),
        ),
      );

      controller.undo();

      expect(
        controller.value, equals(
          AmphitheatreEditorModifications(
            crop: AmphitheatreEditorActionCrop(
              start: Duration.zero,
              end: const Duration(milliseconds: 200),
            ),
          ),
        ),
      );

      controller.undo();
      expect(controller.value, equals(const AmphitheatreEditorModifications.empty()));

      controller..redo()..redo();

      expect(
        controller.value, equals(
          AmphitheatreEditorModifications(
            crop: AmphitheatreEditorActionCrop(
              start: Duration.zero,
              end: const Duration(milliseconds: 100),
            ),
          ),
        ),
      );

      controller..undo()..undo();
      expect(controller.value, equals(const AmphitheatreEditorModifications.empty()));

      expect(controller.hasUndo, isFalse);
      expect(controller.hasRedo, isTrue);

      controller.crop(start: Duration.zero, end: const Duration(milliseconds: 300));
      expect(controller.hasUndo, isTrue);
      expect(controller.hasRedo, isFalse);

      controller.undo();
      expect(controller.value, equals(const AmphitheatreEditorModifications.empty()));
      expect(controller.hasUndo, isFalse);
      expect(controller.hasUndo, isFalse);
    });

    test('new action after undo resets redo stack', () {
      final controller = AmphitheatreEditorController();
      expect(controller.hasUndo, isFalse);
      expect(controller.hasRedo, isFalse);

      controller
        ..crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 200),
        )
        ..crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 100),
        );
      
      expect(controller.hasUndo, isTrue);
      expect(controller.hasRedo, isFalse);

      controller.undo();
      expect(controller.hasUndo, isTrue);
      expect(controller.hasRedo, isTrue);

      controller.crop(start: Duration.zero, end: const Duration(milliseconds: 300));
      expect(controller.hasUndo, isTrue);
      expect(controller.hasRedo, isFalse);

      controller.undo();
      expect(
        controller.value, equals(
          AmphitheatreEditorModifications(
            crop: AmphitheatreEditorActionCrop(
              start: Duration.zero,
              end: const Duration(milliseconds: 200),
            ),
          ),
        ),
      );

      expect(controller.hasUndo, isTrue);
      expect(controller.hasRedo, isTrue);

      controller.redo();
      expect(
        controller.value, equals(
          AmphitheatreEditorModifications(
            crop: AmphitheatreEditorActionCrop(
              start: Duration.zero,
              end: const Duration(milliseconds: 300),
            ),
          ),
        ),
      );

      controller.undo();
      expect(controller.hasUndo, isTrue);
      expect(controller.hasRedo, isTrue);
      expect(
        controller.value, equals(
          AmphitheatreEditorModifications(
            crop: AmphitheatreEditorActionCrop(
              start: Duration.zero,
              end: const Duration(milliseconds: 200),
            ),
          ),
        ),
      );

      controller.undo();
      expect(controller.hasUndo, isFalse);
      expect(controller.hasRedo, isTrue);
      expect(controller.value, equals(const AmphitheatreEditorModifications.empty()));
    });

    test('returns false for hasModification and for hasUndo after an exhaustive undo', () {
      final controller = AmphitheatreEditorController();
      expect(controller.hasModification, isFalse);
      expect(controller.hasUndo, isFalse);

      controller
        ..crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 200),
        )
        ..crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 100),
        );

      expect(controller.hasModification, isTrue);
      expect(controller.hasUndo, isTrue);

      // Undo the first change.
      controller.undo();
      expect(controller.hasModification, isTrue);
      expect(controller.hasUndo, isTrue);

      // Undo the last changes.
      controller.undo();
      expect(controller.hasModification, isFalse);
      expect(controller.hasUndo, isFalse);
    });

    test('clearHistory removes all redo and undo actions but retains modifications', () {
      final controller = AmphitheatreEditorController();
      expect(controller.hasModification, isFalse);
      expect(controller.hasUndo, isFalse);
      expect(controller.hasRedo, isFalse);

      controller
        ..crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 200),
        )
        ..crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 100),
        )
        ..undo();

      expect(controller.hasModification, isTrue);
      expect(controller.hasUndo, isTrue);
      expect(controller.hasRedo, isTrue);

      controller.clearHistory();
      expect(controller.hasModification, isTrue);
      expect(controller.hasUndo, isFalse);
      expect(controller.hasRedo, isFalse);
    });

    test('reset removes all redo and undo actions and modifications', () {
      final controller = AmphitheatreEditorController();
      expect(controller.hasModification, isFalse);
      expect(controller.hasUndo, isFalse);
      expect(controller.hasRedo, isFalse);

      controller
        ..crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 200),
        )
        ..crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 100),
        )
        ..undo();

      expect(controller.hasModification, isTrue);
      expect(controller.hasUndo, isTrue);
      expect(controller.hasRedo, isTrue);

      controller.reset();
      expect(controller.hasModification, isFalse);
      expect(controller.hasUndo, isFalse);
      expect(controller.hasRedo, isFalse);
    });

    test('returns true for hasModification but false for hasUndo after history is cleared', () {
      final controller = AmphitheatreEditorController();
      expect(controller.hasModification, isFalse);
      expect(controller.hasUndo, isFalse);

      controller
        ..crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 200),
        )
        ..crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 100),
        );

      expect(controller.hasModification, isTrue);
      expect(controller.hasUndo, isTrue);

      controller.clearHistory();
      expect(controller.hasModification, isTrue);
      expect(controller.hasUndo, isFalse);
    });

    test('stores only up to ${AmphitheatreEditorController.kMaxHistoryLength} (kMaxHistoryLength) changes', () {
      final controller = AmphitheatreEditorController();
      expect(controller.hasModification, isFalse);
      expect(controller.hasUndo, isFalse);

      for (var i = 0; i < AmphitheatreEditorController.kMaxHistoryLength + 2; i++) {
        controller.crop(start: Duration.zero, end: Duration(milliseconds: i + 1));
      }

      expect(controller.hasModification, isTrue);
      expect(controller.hasUndo, isTrue);

      // Undo the kMaxHistoryLength number of changes and prove that there are
      // no more undo actions left.
      for (var i = 0; i < AmphitheatreEditorController.kMaxHistoryLength; i++) {
        controller.undo();
      }

      expect(controller.hasModification, isTrue);
      expect(controller.hasUndo, isFalse);

      // Now prove the two extra undos do nothing.
      controller..undo()..undo();
      expect(controller.hasModification, isTrue);
      expect(controller.hasUndo, isFalse);

      // Now prove there are exactly kMaxHistoryLength redos.
      expect(controller.hasRedo, isTrue);
      var redos = 0;
      while (controller.hasRedo) {
        redos++;
        controller.redo();
      }

      // (Prove the above by showing we have exhausted all redos after
      // kMaxHistoryLength).
      expect(redos, equals(AmphitheatreEditorController.kMaxHistoryLength));
      expect(controller.hasRedo, isFalse);
    });

    group('notifies listeners', () {

      late AmphitheatreEditorController controller;
      late int receivedEvents;

      setUp(() {
        controller = AmphitheatreEditorController();
        receivedEvents = 0;

        expect(receivedEvents, equals(0));
        controller.addListener(() {
          receivedEvents++;
        });

        // This action should not have notified.
        expect(receivedEvents, equals(0));
      });

      test('on modification', () async {
        controller.crop(start: Duration.zero, end: const Duration(milliseconds: 200));
        await expectLater(receivedEvents, equals(1));
      });

      test('on undo', () async {
        controller.crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 200),
        );
        await expectLater(receivedEvents, equals(1));

        // Trigger a second event to have multiple in the history stack.
        controller.crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 100),
        );
        await expectLater(receivedEvents, equals(2));

        // Trigger an undo once.
        controller.undo();
        await expectLater(receivedEvents, equals(3));

        // Trigger an undo again. 
        controller.undo();
        await expectLater(receivedEvents, equals(4));

        // The stack is now empty so no further events should be generated. 
        controller.undo();
        await expectLater(receivedEvents, equals(4));
      });

      test('on redo', () async {
        controller.crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 200),
        );
        await expectLater(receivedEvents, equals(1));

        // Trigger a second event to have multiple in the history stack.
        controller.crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 100),
        );
        await expectLater(receivedEvents, equals(2));

        // Trigger an undo once.
        controller.undo();
        await expectLater(receivedEvents, equals(3));

        // Trigger an undo again. 
        controller.undo();
        await expectLater(receivedEvents, equals(4));

        // Trigger a redo.
        controller.redo();
        await expectLater(receivedEvents, equals(5));

        // Trigger a redo again.
        controller.redo();
        await expectLater(receivedEvents, equals(6));

        // The stack is now empty so no further events should be generated. 
        controller.redo();
        await expectLater(receivedEvents, equals(6));
      });

      test('on history clear', () async {
        controller.crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 200),
        );
        await expectLater(receivedEvents, equals(1));
        expect(controller.hasUndo, isTrue);

        // Clear the history.
        controller.clearHistory();
        await expectLater(receivedEvents, equals(2));
        expect(controller.hasUndo, isFalse);

        // Expect subsequent calls to clearHistory to notify (even when the
        // history stack is empty). This is not necessarily required or
        // semantically correct behavior, but this test is here to catch
        // changes that might later cause issues.
        controller.clearHistory();
        await expectLater(receivedEvents, equals(3));
        expect(controller.hasUndo, isFalse);
      });

      test('on reset', () async {
        controller.crop(
          start: Duration.zero,
          end: const Duration(milliseconds: 200),
        );
        await expectLater(receivedEvents, equals(1));
        expect(controller.hasUndo, isTrue);

        // Reset modifications.
        controller.reset();
        await expectLater(receivedEvents, equals(2));
        expect(controller.hasUndo, isFalse);

        // Expect subsequent calls to reset to notify (even when the
        // history stack is empty). This is not necessarily required or
        // semantically correct behavior, but this test is here to catch
        // changes that might later cause issues.
        controller.reset();
        await expectLater(receivedEvents, equals(3));
        expect(controller.hasUndo, isFalse);
      });
      
    });

  });
}
