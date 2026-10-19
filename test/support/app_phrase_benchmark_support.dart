import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// Fails closed when an explicitly requested baseline cannot prove equivalence.
Map<String, Map<String, dynamic>> parseBenchmarkReferences(
  Iterable<String> lines,
  Set<String> expectedIds,
) {
  final references = <String, Map<String, dynamic>>{};
  for (final line in lines) {
    if (!line.startsWith('TAWROW ')) continue;
    final value = jsonDecode(line.substring(7));
    if (value is! Map<String, dynamic> ||
        value['id'] is! String ||
        value['layout'] is! Map<String, dynamic> ||
        value['exactLayout'] is! Map<String, dynamic>) {
      throw StateError(
        'Reference rows require an id, layout, and unbounded exactLayout.',
      );
    }
    final id = value['id'] as String;
    final previous = references[id];
    if (previous != null &&
        (!equals(previous['layout']).matches(value['layout'], {}) ||
            !equals(
              previous['exactLayout'],
            ).matches(value['exactLayout'], {}))) {
      throw StateError('Reference geometry changed between repetitions: $id');
    }
    references[id] = value;
  }
  if (references.isEmpty ||
      references.keys.toSet().difference(expectedIds).isNotEmpty ||
      expectedIds.difference(references.keys.toSet()).isNotEmpty) {
    throw StateError(
      'Reference conditions do not match the requested benchmark.',
    );
  }
  return references;
}

void validateBenchmarkConfiguration({
  required int repetitions,
  required int rounds,
}) {
  if (repetitions <= 0 || rounds <= 0) {
    throw ArgumentError('TAW_REPS and TAW_ROUNDS must both be positive.');
  }
}
