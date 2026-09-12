// Preset metadata: semantic-wrap, Copyright 2026 Woohyun Park, Apache-2.0.
// Source: packages/{en,ko}/MODEL_CARD.md at commit
// 54ed67688aa5292f14970cae10bbabd9a11f1b5d (see NOTICE and LICENSE).
// Modified for text_auto_wrap in 2026: lazy Dart presets and whitespace-boundary
// adapters for the immutable PhraseModel API.
library;

export 'src/core/boundaries.dart';
export 'src/core/exceptions.dart';
export 'src/core/layout.dart';
export 'src/core/models.dart';
export 'src/core/prediction.dart';
export 'src/core/selection.dart';
export 'src/core/strategy.dart';
export 'src/core/diagnostics.dart';
export 'src/core/plan.dart';
export 'src/core/select_text_wrap.dart';
export 'src/models/budoux_parser.dart';
export 'src/models/language_detection.dart';

const String textAutoWrapVersion = '0.1.0';
