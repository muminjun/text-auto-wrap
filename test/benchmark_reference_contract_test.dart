import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'support/app_phrase_benchmark_support.dart' as benchmark;

void main() {
  var lines = <String>[];
  Map<String, Object?> row(String id, {int width = 10}) => {
    'id': id,
    'layout': {
      'widths': [width],
    },
    'exactLayout': {
      'widths': [width],
    },
  };
  void write(List<Map<String, Object?>> rows) {
    lines = rows.map((row) => 'TAWROW ${jsonEncode(row)}').toList();
  }

  test('a requested comparison rejects a log without reference rows', () {
    lines = ['benchmark skipped'];
    expect(
      () => benchmark.parseBenchmarkReferences(lines, {'case'}),
      throwsStateError,
    );
  });
  test('a comparison rejects missing conditions', () {
    write([row('a')]);
    expect(
      () => benchmark.parseBenchmarkReferences(lines, {'a', 'b'}),
      throwsStateError,
    );
  });
  test('a comparison requires an unbounded oracle', () {
    final value = row('case')..['exactLayout'] = null;
    write([value]);
    expect(
      () => benchmark.parseBenchmarkReferences(lines, {'case'}),
      throwsStateError,
    );
  });
  test('inconsistent repeated reference geometry is rejected', () {
    write([row('case'), row('case', width: 11)]);
    expect(
      () => benchmark.parseBenchmarkReferences(lines, {'case'}),
      throwsStateError,
    );
  });
  test('consistent repeated conditions are accepted', () {
    write([row('case'), row('case')]);
    expect(benchmark.parseBenchmarkReferences(lines, {'case'}), {
      'case': row('case'),
    });
  });
  test('zero and negative repetition counts cannot pass without samples', () {
    for (final (repetitions, rounds) in [(0, 1), (1, 0), (-1, 1), (1, -1)]) {
      expect(
        () => benchmark.validateBenchmarkConfiguration(
          repetitions: repetitions,
          rounds: rounds,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => benchmark.validateBenchmarkConfiguration(repetitions: 1, rounds: 1),
      returnsNormally,
    );
  });
}
