import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'services/text_to_speech_service.dart';
import 'services/translation_service.dart';

void main() {
  runApp(const TranslatorApp());
}

class TranslatorApp extends StatelessWidget {
  const TranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Translator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const TranslatorHomePage(),
    );
  }
}

class TranslationLanguage implements TranslationLanguageLike {
  const TranslationLanguage({
    required this.code,
    required this.label,
    required this.ttsLocale,
  });

  @override
  final String code;
  final String label;
  final String ttsLocale;
}

const translationTargets = [
  TranslationLanguage(code: 'en', label: 'English', ttsLocale: 'en-US'),
  TranslationLanguage(code: 'es', label: 'Spanish', ttsLocale: 'es-ES'),
  TranslationLanguage(code: 'zh-cn', label: 'Chinese (Simplified)', ttsLocale: 'zh-CN'),
  TranslationLanguage(code: 'tl', label: 'Tagalog', ttsLocale: 'fil-PH'),
  TranslationLanguage(code: 'vi', label: 'Vietnamese', ttsLocale: 'vi-VN'),
  TranslationLanguage(code: 'ar', label: 'Arabic', ttsLocale: 'ar-SA'),
  TranslationLanguage(code: 'fr', label: 'French', ttsLocale: 'fr-FR'),
  TranslationLanguage(code: 'ko', label: 'Korean', ttsLocale: 'ko-KR'),
];

const defaultPlaybackLanguageCode = 'en';

class TranslatorHomePage extends StatefulWidget {
  const TranslatorHomePage({super.key});

  @override
  State<TranslatorHomePage> createState() => _TranslatorHomePageState();
}

class _TranslatorHomePageState extends State<TranslatorHomePage> {
  final speechToText = SpeechToText();
  final translationService = TranslationService();
  final textController = TextEditingController();
  final ttsService = TextToSpeechService();

  String? speechLocaleId;

  bool isListening = false;
  bool speechReady = false;
  bool textTranslating = false;
  bool voiceTranslating = false;
  String voiceTranscript = '';
  String statusMessage = 'Tap the mic to start listening';
  String? textDetectedLanguage;
  String? voiceDetectedLanguage;

  Map<String, String> textTranslations = {};
  Map<String, String> voiceTranslations = {};
  TranslationLanguage selectedTarget = translationTargets.first;

  Timer? textDebounce;
  int textRequestId = 0;
  int voiceRequestId = 0;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  List<TranslationLanguage> get activeTranslationTargets => [selectedTarget];

  Future<void> _initSpeech() async {
    try {
      final available = await speechToText.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
      );
      if (!mounted) {
        return;
      }
      final systemLocale =
          available ? await speechToText.systemLocale() : null;
      if (!mounted) {
        return;
      }
      setState(() {
        speechReady = available;
        speechLocaleId = systemLocale?.localeId ?? speechLocaleId ?? 'en_US';
        if (!available) {
          statusMessage =
              'Speech recognition is not available on this device.';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        speechReady = false;
        statusMessage = 'Could not initialize speech recognition';
        speechLocaleId ??= 'en_US';
      });
    }
  }

  Future<void> _toggleListening() async {
    if (isListening) {
      await speechToText.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        isListening = false;
        statusMessage = 'Tap the mic to start listening';
      });
      return;
    }

    if (!speechReady) {
      await _initSpeech();
    }
    if (!speechReady) {
      _showError('Speech recognition is not available.');
      return;
    }

    final available = await speechToText.hasPermission;
    if (!available) {
      _showError('Microphone permission is required to listen.');
      return;
    }

    setState(() {
      voiceTranscript = '';
      voiceTranslations = {};
      voiceDetectedLanguage = null;
      voiceTranslating = false;
      statusMessage = 'Listening...';
      isListening = true;
    });
    await ttsService.stop();

    final localeId = speechLocaleId ?? 'en_US';
    await speechToText.listen(
      localeId: localeId,
      onResult: _handleSpeechResult,
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
      ),
    );
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    final recognized = result.recognizedWords.trim();
    if (!mounted) {
      return;
    }
    setState(() {
      voiceTranscript = recognized;
      statusMessage = result.finalResult ? 'Processing...' : 'Listening...';
      voiceTranslating = result.finalResult;
    });

    if (result.finalResult) {
      unawaited(_translateVoice(recognized));
    }
  }

  Future<void> _translateVoice(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      if (!mounted) return;
      setState(() {
        voiceTranslations = {};
        voiceDetectedLanguage = null;
        voiceTranslating = false;
      });
      await ttsService.stop();
      return;
    }
    final currentRequest = ++voiceRequestId;
    setState(() => voiceTranslating = true);
    final targets = activeTranslationTargets;
    if (targets.isEmpty) {
      setState(() {
        voiceTranslations = {};
        voiceDetectedLanguage = null;
        voiceTranslating = false;
        statusMessage = 'Tap the mic to start listening';
      });
      return;
    }
    try {
      final result = await translationService.translateToTargets(
        text: trimmed,
        targets: targets,
      );
      if (!mounted || currentRequest != voiceRequestId) {
        return;
      }
      setState(() {
        voiceTranslations = result.translations;
        voiceDetectedLanguage = result.detectedLanguageName;
        voiceTranslating = false;
        statusMessage = 'Tap the mic to start listening';
      });
      await _speakPrimaryTranslation(result.translations);
    } catch (error) {
      if (!mounted || currentRequest != voiceRequestId) {
        return;
      }
      _showError('Unable to translate voice input. Please try again.');
      setState(() {
        voiceTranslating = false;
        statusMessage = 'Tap the mic to start listening';
      });
    }
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) {
      return;
    }
    if (status == 'notListening') {
      setState(() {
        isListening = false;
        statusMessage = 'Tap the mic to start listening';
      });
    }
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    if (!mounted) {
      return;
    }
    _showError(error.errorMsg);
    setState(() {
      isListening = false;
      statusMessage = 'Tap the mic to try again';
    });
  }

  void _onTypedText(String value) {
    textDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        textTranslations = {};
        textDetectedLanguage = null;
      });
      return;
    }
    textDebounce = Timer(const Duration(milliseconds: 350), () {
      _translateTyped(value);
    });
  }

  Future<void> _translateTyped(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        textTranslations = {};
        textDetectedLanguage = null;
        textTranslating = false;
      });
      return;
    }
    final currentRequest = ++textRequestId;
    setState(() => textTranslating = true);
    final targets = activeTranslationTargets;
    if (targets.isEmpty) {
      setState(() {
        textTranslations = {};
        textDetectedLanguage = null;
        textTranslating = false;
      });
      return;
    }
    try {
      final result = await translationService.translateToTargets(
        text: trimmed,
        targets: targets,
      );
      if (!mounted || currentRequest != textRequestId) {
        return;
      }
      setState(() {
        textTranslations = result.translations;
        textDetectedLanguage = result.detectedLanguageName;
        textTranslating = false;
      });
    } catch (error) {
      if (!mounted || currentRequest != textRequestId) {
        return;
      }
      _showError('Unable to translate text input. Check your connection.');
      setState(() => textTranslating = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
      ),
    );
  }

  void _handleTargetSelection(String code) {
    final language = translationTargets.firstWhere((item) => item.code == code,
        orElse: () => translationTargets.first);
    setState(() {
      selectedTarget = language;
    });
    _rerunActiveTranslations();
  }

  void _rerunActiveTranslations() {
    final typed = textController.text.trim();
    if (typed.isNotEmpty) {
      _translateTyped(typed);
    }
    if (voiceTranscript.trim().isNotEmpty && !voiceTranslating) {
      unawaited(_translateVoice(voiceTranscript));
    }
  }

  @override
  void dispose() {
    textDebounce?.cancel();
    textController.dispose();
    speechToText.stop();
    ttsService.dispose();
    super.dispose();
  }

  Future<void> _speakPrimaryTranslation(Map<String, String> translations) async {
    final targets = activeTranslationTargets;
    if (targets.isEmpty) {
      return;
    }
    final target = targets.firstWhere(
      (language) => language.code == defaultPlaybackLanguageCode,
      orElse: () => targets.first,
    );
    final text = translations[target.code];
    if (text == null || text.trim().isEmpty) {
      return;
    }
    await _speakText(target, text);
  }

  Future<void> _speakText(TranslationLanguage language, String text) async {
    try {
      await ttsService.configureLocale(language.ttsLocale);
      await ttsService.speak(text);
    } catch (_) {
      // Ignore playback failures to keep UI responsive.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live voice & text translator'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TranslationLanguageSelector(
                targets: translationTargets,
                selectedTarget: selectedTarget,
                onChanged: _handleTargetSelection,
              ),
              const SizedBox(height: 24),
              _SectionCard(
                title: 'Type to translate',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: textController,
                      maxLines: null,
                      onChanged: _onTypedText,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Source text',
                        hintText: 'Start typing to translate instantly',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _TranslationResults(
                      translations: textTranslations,
                      targets: activeTranslationTargets,
                      detectedLanguage: textDetectedLanguage,
                      isLoading: textTranslating,
                      onSpeak: (target, text) => _speakText(target, text),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SectionCard(
                title: 'Speak to translate',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isListening ? Icons.mic : Icons.mic_none,
                          color: isListening
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            statusMessage,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _toggleListening,
                          icon: Icon(isListening ? Icons.stop : Icons.mic),
                          label: Text(isListening ? 'Stop' : 'Listen'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Transcript',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Text(
                        voiceTranscript.isEmpty
                            ? 'Speak to see the live transcript.'
                            : voiceTranscript,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _TranslationResults(
                      translations: voiceTranslations,
                      targets: activeTranslationTargets,
                      detectedLanguage: voiceDetectedLanguage,
                      isLoading: voiceTranslating,
                      onSpeak: (target, text) => _speakText(target, text),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TranslationLanguageSelector extends StatelessWidget {
  const _TranslationLanguageSelector({
    required this.targets,
    required this.selectedTarget,
    required this.onChanged,
  });

  final List<TranslationLanguage> targets;
  final TranslationLanguage selectedTarget;
  final void Function(String code) onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Translation language',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the language you want the app to translate into.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedTarget.code,
                  isExpanded: true,
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
          ],
        ),
      ),
    );
  }
}

class _TranslationResults extends StatelessWidget {
  const _TranslationResults({
    required this.translations,
    required this.targets,
    required this.detectedLanguage,
    required this.onSpeak,
    this.isLoading = false,
  });

  final Map<String, String> translations;
  final List<TranslationLanguage> targets;
  final String? detectedLanguage;
  final bool isLoading;
  final Future<void> Function(TranslationLanguage target, String text) onSpeak;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasTargets = targets.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.language,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                detectedLanguage == null
                    ? 'Detected language: awaiting input'
                    : 'Detected language: $detectedLanguage',
                style: textTheme.labelLarge,
              ),
            ),
          ],
        ),
        if (isLoading && hasTargets) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ] else
          const SizedBox(height: 8),
        if (!hasTargets)
          Text(
            'Select at least one translation language above to see results.',
            style: textTheme.bodyMedium,
          )
        else
          ...targets.map((target) {
            final text = translations[target.code] ?? '';
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 0,
              child: ListTile(
                title: Text(target.label),
                subtitle: Text(
                  text.isEmpty
                      ? 'Translation will appear here.'
                      : text,
                  style: textTheme.bodyLarge,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.volume_up),
                  onPressed: text.isEmpty ? null : () => onSpeak(target, text),
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
