import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/diagnostics.dart';
import '../core/layout.dart';
import '../core/prediction.dart';

/// Publishes the most recently committed text-wrap selection after layout.
///
/// The value is assigned synchronously so layout clients can inspect it right
/// away. Listener notification is deferred to the end of the frame to avoid a
/// reentrant build while a [RenderTextAutoWrap] is laying out.
final class TextAutoWrapController extends ChangeNotifier {
  TextWrapResult? _result;
  Object? _owner;
  var _generation = 0;
  var _notificationScheduled = false;
  var _disposed = false;

  /// The latest immutable selection committed by an attached renderer.
  TextWrapResult? get result => _result;

  /// Alias for [result] for value-listenable-style consumers.
  TextWrapResult? get value => _result;

  /// Internal renderer hook; notifies after the current frame.
  void commitResult(Object owner, TextWrapResult value) {
    if (_disposed) return;
    final materiallyEquivalent = _sameResult(_result, value);
    _result = value;
    if (materiallyEquivalent) return;
    if (_notificationScheduled && identical(_owner, owner)) return;
    _owner = owner;
    _schedule(owner);
  }

  /// Internal renderer hook; invalidates a pending renderer notification.
  void detachOwner(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _generation++;
    _notificationScheduled = false;
  }

  void _schedule(Object owner) {
    _notificationScheduled = true;
    final generation = ++_generation;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed ||
          !_notificationScheduled ||
          generation != _generation ||
          !identical(_owner, owner)) {
        return;
      }
      _notificationScheduled = false;
      _owner = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _owner = null;
    _generation++;
    _notificationScheduled = false;
    super.dispose();
  }
}

bool _sameResult(TextWrapResult? left, TextWrapResult right) {
  if (identical(left, right)) return true;
  if (left == null ||
      left.applied != right.applied ||
      left.reason != right.reason ||
      left.source != right.source ||
      left.overflow != right.overflow) {
    return false;
  }
  final leftLayout = left.layout;
  final rightLayout = right.layout;
  if (leftLayout.sourceText != rightLayout.sourceText ||
      leftLayout.lineCount != rightLayout.lineCount ||
      leftLayout.totalModelCost != rightLayout.totalModelCost ||
      !_sameInts(left.breakOffsets, right.breakOffsets) ||
      !_sameRanges(left.ranges, right.ranges) ||
      !_sameDoubles(left.widths, right.widths) ||
      !_sameCandidates(
        leftLayout.selectedCandidates,
        rightLayout.selectedCandidates,
      )) {
    return false;
  }
  return true;
}

bool _sameCandidates(List<BreakCandidate> left, List<BreakCandidate> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    final leftCandidate = left[index];
    final rightCandidate = right[index];
    if (leftCandidate.offset != rightCandidate.offset ||
        leftCandidate.penalty != rightCandidate.penalty ||
        leftCandidate.levelName != rightCandidate.levelName ||
        leftCandidate.consensusCount != rightCandidate.consensusCount ||
        leftCandidate.isFallback != rightCandidate.isFallback) {
      return false;
    }
  }
  return true;
}

bool _sameInts(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameRanges(List<TextLineRange> left, List<TextLineRange> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index].start != right[index].start ||
        left[index].end != right[index].end) {
      return false;
    }
  }
  return true;
}

bool _sameDoubles(List<double> left, List<double> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
