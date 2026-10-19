import 'models.dart';

/// Marks predictors implemented by this package.
///
/// Their output is validated by construction and tests, so the engine may skip
/// prediction when the native layout cannot be improved. It is deliberately not
/// exported: caller-supplied predictors keep full validation and failure
/// reporting for every layout.
abstract interface class LibraryBoundaryPredictor
    implements BoundaryPredictor {}
