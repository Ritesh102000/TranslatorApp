import 'package:flutter/material.dart';

import '../models/translation_language.dart';

class TranslationResults extends StatelessWidget {
  const TranslationResults({
    super.key,
    required this.translations,
    required this.targets,
    required this.detectedLanguage,
    required this.onSpeak,
    this.isLoading = false,
    this.emptyMessage = 'Translation appears here.',
    this.speakerKeyPrefix,
  });

  final Map<String, String> translations;
  final List<TranslationLanguage> targets;
  final String? detectedLanguage;
  final bool isLoading;
  final String emptyMessage;
  final String? speakerKeyPrefix;
  final Future<void> Function(TranslationLanguage target, String text) onSpeak;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.language, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  detectedLanguage == null
                      ? 'Detected language: waiting for input'
                      : 'Detected language: $detectedLanguage',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (isLoading) ...[
          const LinearProgressIndicator(minHeight: 4),
          const SizedBox(height: 12),
        ],
        ...targets.map((target) {
          final text = translations[target.code]?.trim() ?? '';
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        target.label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      key: speakerKeyPrefix == null
                          ? null
                          : Key('${speakerKeyPrefix!}_${target.code}_speak'),
                      tooltip: 'Play translation',
                      icon: const Icon(Icons.volume_up_rounded),
                      onPressed: text.isEmpty
                          ? null
                          : () => onSpeak(target, text),
                    ),
                  ],
                ),
                Text(
                  text.isEmpty ? emptyMessage : text,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
