part of 'amphitheatre_editor.dart';

/// The base class for actions that can be performed by the
/// [AmphitheatreEditor].
@immutable
sealed class AmphitheatreEditorAction {
  /// The unique ID of the crop action. Prefer using the end of the class name
  /// for this to guarantee uniqueness (e.g., [AmphitheatreEditorActionCrop]
  /// would become 'crop').
  String get id;

  const AmphitheatreEditorAction();

  /// Converts the action to a JSON representation. (Typically a
  /// `Map<String, dynamic`).
  dynamic toJson();
}

/// A crop action. This is when the duration of the video is shortened to a
/// subset within the original video.
final class AmphitheatreEditorActionCrop extends AmphitheatreEditorAction {
  @override
  String get id => 'crop';

  /// The start time in the original video.
  final Duration start;

  /// The end time in the original video.
  final Duration end;

  /// Construct an [AmphitheatreEditorActionCrop].
  const AmphitheatreEditorActionCrop({required this.start, required this.end})
      : assert(end > start, 'end cannot precede or equal start');

  @override
  Map<String, int> toJson() =>
      {'start': start.inMilliseconds, 'end': end.inMilliseconds};

  @override
  bool operator ==(final Object other) =>
      other is AmphitheatreEditorActionCrop &&
      start == other.start &&
      end == other.end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// The controller for an [AmphitheatreEditor]. This is used in addition to the
/// [AmphitheatreController] (which is for the video) to control the edit
/// actions that should be applied to the video.
final class AmphitheatreEditorController with ChangeNotifier {
  AmphitheatreEditorModifications _value =
      const AmphitheatreEditorModifications.empty();
  
  /// The maximum number of history items to retain.
  static const kMaxHistoryLength = 32;

  /// The stack of history items.
  final MaxSizeStack<AmphitheatreEditorModifications> _history = MaxSizeStack(kMaxHistoryLength);

  /// The stack of 'redo' history items.
  /// 
  /// When history items are undone with [undo], the latest modifications are
  /// written here.
  final MaxSizeStack<AmphitheatreEditorModifications> _future = MaxSizeStack(kMaxHistoryLength);

  /// The current set of editor modifications.
  AmphitheatreEditorModifications get value => _value;

  /// Whether a modification has been applied to the video.
  bool get hasModification => value.isNotEmpty;

  /// Whether there are history items (i.e., whether [undo] can be performed).
  bool get hasUndo => _history.isNotEmpty;

  /// Whether there are redo items (i.e., wehether [redo] can be performed).
  bool get hasRedo => _future.isNotEmpty;

  /// If [value] is different to [_value], applies the new [value] in its place,
  /// moving the old value to the end of the [_history] queue.
  /// 
  /// If [writeHistory] is true, the action is written to the history stack.
  /// This allows a user to undo the action. This is not done automatically to
  /// avoid writing unnecessary or excessive history items.
  void _applyNewValue(
    final AmphitheatreEditorModifications value, {
    required final bool writeHistory,
  }) {
    if (_value == value) {
      notifyListeners();
      return;
    }

    _future.clear();
    if (writeHistory) {
      // Push the new history entry onto the stack.
      _history.push(_value);
    }

    _value = value;
    notifyListeners();
  }

  /// Crop the video length to only retain the part between [start] and [end].
  ///
  /// See [AmphitheatreEditorActionCrop].
  void crop({
    required final Duration start,
    required final Duration end,
    final bool writeHistory = true,
  }) =>
      _applyNewValue(
        value.copyWith(
          crop: AmphitheatreEditorActionCrop(start: start, end: end),
        ),
        writeHistory: writeHistory,
      );
  
  /// Undo the last edit.
  void undo() {
    if (_history.isNotEmpty) {
      _future.push(_value);
      _value = _history.pop();
      notifyListeners();
    }
  }

  /// Redo the last edit.
  void redo() {
    if (_future.isNotEmpty) {
      _history.push(_value);
      _value = _future.pop();
      notifyListeners();
    }
  }

  /// Clear the history stack.
  /// 
  /// Note that this just clears the metadata about the changes preventing them
  /// from being undone with [undo] or redone with [redo]. This does not clear
  /// the changes themselves.
  /// 
  /// To clear the modifications too, use [reset] instead.
  void clearHistory() {
    _history.clear();
    _future.clear();
    notifyListeners();
  }

  /// Reset all modifications.
  /// 
  /// Unlike [clearHistory], this clears the history and all modifications to
  /// the video.
  void reset() {
    _value = const AmphitheatreEditorModifications.empty();
    clearHistory();
  }
}

/// The set of modifications to be applied to a video.
@immutable
final class AmphitheatreEditorModifications {
  /// See [AmphitheatreEditorActionCrop].
  final AmphitheatreEditorActionCrop? crop;

  /// Construct a set of [AmphitheatreEditorModifications].
  const AmphitheatreEditorModifications({required this.crop});

  /// Construct a new, empty, set of [AmphitheatreEditorModifications].
  const AmphitheatreEditorModifications.empty() : this(crop: null);

  List<AmphitheatreEditorAction?> get _modifications => [crop];

  /// If [isEmpty] is true, then no modifications have been made.
  bool get isEmpty => _modifications.nonNulls.isEmpty;

  /// If [isNotEmpty] is true, then at least one modification has been made.
  bool get isNotEmpty => _modifications.nonNulls.isNotEmpty;

  /// Check whether every modification that the
  /// [AmphitheatreEditorModifications] supports have been applied.
  bool get hasEveryModification =>
      _modifications.nonNulls.length == _modifications.length;

  /// Copy the set of modifications with a new modification - either replacing
  /// or adding the modification depending on whether it already exists.
  AmphitheatreEditorModifications copyWith({
    final AmphitheatreEditorActionCrop? crop,
  }) =>
      AmphitheatreEditorModifications(crop: crop ?? this.crop);

  /// Copy the set of modifications, only replacing modifications when the new
  /// one is specified and there is not an existing modification of that type.
  AmphitheatreEditorModifications copyWithUnique({
    final AmphitheatreEditorActionCrop? crop,
  }) =>
      AmphitheatreEditorModifications(
        crop: crop != null && this.crop == null ? crop : this.crop,
      );

  /// Build a JSON representation of the modifications.
  Map<String, AmphitheatreEditorAction> toJson() => _modifications.fold(
        <String, AmphitheatreEditorAction>{},
        (final value, final entry) {
          if (entry == null) return value;
          value[entry.id] = entry;
          return value;
        },
      );

  /// Converts the [toJson] representation to a string.
  String toJsonString() => jsonEncode(toJson());

  /// Returns [toJsonString].
  @override
  String toString() => toJsonString();

  @override
  bool operator ==(final Object other) =>
      other is AmphitheatreEditorModifications && crop == other.crop;

  @override
  int get hashCode => crop.hashCode;
}
