import 'package:flutter/material.dart';

import '../models/translation_language.dart';

class TranslationLanguageSelector extends StatelessWidget {
  const TranslationLanguageSelector({
    super.key,
    required this.targets,
    required this.selectedTarget,
    required this.onChanged,
  });

  final List<TranslationLanguage> targets;
  final TranslationLanguage selectedTarget;
  final void Function(String code) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Target Language', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('targetLanguageDropdown'),
                value: selectedTarget.code,
                isExpanded: true,
                borderRadius: BorderRadius.circular(14),
                menuMaxHeight: 360,
                items: targets
                    .map(
                      (language) => DropdownMenuItem(
                        value: language.code,
                        child: Text(language.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    onChanged(value);
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
