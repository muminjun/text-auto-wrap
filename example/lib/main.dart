import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:text_auto_wrap/text_auto_wrap.dart';

void main() => runApp(const TextAutoWrapExample());

class TextAutoWrapExample extends StatelessWidget {
  const TextAutoWrapExample({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'text_auto_wrap example',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    ),
    home: const ExampleScreen(),
  );
}

class ExampleScreen extends StatefulWidget {
  const ExampleScreen({super.key});

  @override
  State<ExampleScreen> createState() => _ExampleScreenState();
}

class _ExampleScreenState extends State<ExampleScreen> {
  static const _minimumWidth = 220.0;
  static const _maximumWidth = 720.0;

  final _diagnosticsController = TextAutoWrapController();
  double _requestedWidth = 420;

  @override
  void dispose() {
    _diagnosticsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('text_auto_wrap')),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(_minimumWidth, constraints.maxWidth - 32);
        final contentWidth = math.min(_requestedWidth, available).toDouble();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Content width: ${contentWidth.round()} px',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Slider(
              min: _minimumWidth,
              max: _maximumWidth,
              divisions: 25,
              label: _requestedWidth.round().toString(),
              value: _requestedWidth,
              onChanged: (value) => setState(() => _requestedWidth = value),
            ),
            _ExampleCard(
              width: contentWidth,
              title: 'Korean plain text · automatic',
              child: const TextAutoWrap(
                '사용자를 이해하고 더 나은 해결책을 만드는 방법',
                style: _titleStyle,
              ),
            ),
            _ExampleCard(
              width: contentWidth,
              title: 'English plain text · automatic',
              child: const TextAutoWrap(
                'Designing products people trust without slowing down delivery',
                style: _titleStyle,
              ),
            ),
            _ExampleCard(
              width: contentWidth,
              title: 'Styled TextSpan',
              child: TextAutoWrap.rich(
                TextSpan(
                  style: _titleStyle.copyWith(color: Colors.black87),
                  children: const [
                    TextSpan(text: 'Keep the '),
                    TextSpan(
                      text: 'important phrase',
                      style: TextStyle(
                        color: Colors.indigo,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(text: ' easy to read'),
                  ],
                ),
              ),
            ),
            _ExampleCard(
              width: contentWidth,
              title: 'WidgetSpan',
              child: TextAutoWrap.rich(
                TextSpan(
                  style: _titleStyle.copyWith(color: Colors.black87),
                  children: [
                    const TextSpan(text: 'Shipping with a '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Text('stable API'),
                        ),
                      ),
                    ),
                    const TextSpan(text: ' across every Flutter platform'),
                  ],
                ),
              ),
            ),
            _ExampleCard(
              width: contentWidth,
              title: 'Unsupported language · native fallback',
              child: const TextAutoWrap(
                '読みやすいタイトルをデザインする方法',
                style: _titleStyle,
              ),
            ),
            _ExampleCard(
              width: contentWidth,
              title: 'Explicit model selection',
              child: TextAutoWrap(
                'A product name can mix 한국어 and English words',
                model: TextAutoWrapModels.english,
                style: _titleStyle,
              ),
            ),
            _ExampleCard(
              width: contentWidth,
              title: 'Live controller diagnostics',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextAutoWrap(
                    'Measure every selected line with the current Flutter style',
                    controller: _diagnosticsController,
                    model: TextAutoWrapModels.english,
                    style: _titleStyle,
                  ),
                  const SizedBox(height: 12),
                  ListenableBuilder(
                    listenable: _diagnosticsController,
                    builder: (context, _) {
                      final result = _diagnosticsController.result;
                      final cache = result?.diagnostics?.cache;
                      return SelectableText(
                        result == null
                            ? 'Waiting for layout…'
                            : 'reason=${result.reason}\n'
                                  'applied=${result.applied}, '
                                  'lines=${result.lineCount}\n'
                                  'breakOffsets=${result.breakOffsets}\n'
                                  'planHits=${cache?.planHits ?? 0}, '
                                  'selectionCacheHits='
                                  '${cache?.selectionCacheHits ?? 0}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

const _titleStyle = TextStyle(fontSize: 28, fontWeight: FontWeight.w700);

class _ExampleCard extends StatelessWidget {
  const _ExampleCard({
    required this.width,
    required this.title,
    required this.child,
  });

  final double width;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: SizedBox(
      width: width,
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}
