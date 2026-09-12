/// Base class for text auto-wrap failures caused by invalid public input.
sealed class TextWrapException implements Exception {
  const TextWrapException(this.message);

  /// A human-readable explanation of the invalid input.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when an offset cannot safely represent a text break boundary.
final class InvalidBoundaryException extends TextWrapException {
  const InvalidBoundaryException(super.message);
}

/// Thrown when a model configuration violates its public contract.
final class InvalidModelConfigurationException extends TextWrapException {
  const InvalidModelConfigurationException(super.message);
}

/// Thrown when a range measurement cannot be used for layout calculation.
final class TextRangeMeasurementException extends TextWrapException {
  const TextRangeMeasurementException(super.message);
}
