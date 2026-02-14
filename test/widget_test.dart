import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:translator_appdf/features/translator/models/translation_language.dart';
import 'package:translator_appdf/features/translator/models/voice_pipeline_state.dart';
import 'package:translator_appdf/features/translator/translator_home_page.dart';
import 'package:translator_appdf/features/translator/widgets/voice_status_badge.dart';
import 'package:translator_appdf/services/text_to_speech_service.dart';
import 'package:translator_appdf/services/translation_service.dart';

void main() {
  testWidgets('typed flow translates and shows detected language', (
    tester,
  ) async {
    final fakeTranslation = _FakeTranslationService();
    final fakeTts = _FakeTtsService();

    await _pumpTranslator(
      tester,
      translationService: fakeTranslation,
      ttsService: fakeTts,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('typedInputField')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('typedInputField')),
      'hello world',
    );
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pumpAndSettle();

    expect(find.textContaining('Detected language: English'), findsOneWidget);
    expect(find.text('hello world -> en'), findsOneWidget);
  });

  testWidgets('language selector supports 20 major U.S. languages', (
    tester,
  ) async {
    final fakeTranslation = _FakeTranslationService();
    final fakeTts = _FakeTtsService();

    await _pumpTranslator(
      tester,
      translationService: fakeTranslation,
      ttsService: fakeTts,
    );

    expect(translationTargets.length, greaterThanOrEqualTo(20));
    expect(translationTargets.map((item) => item.code), contains('ht'));
    expect(translationTargets.map((item) => item.code), contains('fa'));

    await tester.tap(find.byKey(const Key('targetLanguageDropdown')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chinese (Traditional)').last);
    await tester.pumpAndSettle();

    final dropdown = tester.widget<DropdownButton<String>>(
      find.byKey(const Key('targetLanguageDropdown')),
    );
    expect(dropdown.value, 'zh-tw');
  });

  testWidgets(
    'voice session auto-speaks once and ignores duplicate final callback',
    (tester) async {
      final stateKey = GlobalKey<TranslatorHomePageState>();
      final fakeTranslation = _FakeTranslationService();
      final fakeTts = _FakeTtsService();

      await _pumpTranslator(
        tester,
        key: stateKey,
        translationService: fakeTranslation,
        ttsService: fakeTts,
      );

      await stateKey.currentState!.debugCompleteVoiceSession(
        'voice hello',
        sessionId: 101,
      );
      await tester.pumpAndSettle();

      expect(fakeTranslation.callCount, 1);
      expect(fakeTts.speakCallCount, 1);

      await stateKey.currentState!.debugEmitFinalVoiceResult(
        sessionId: 101,
        transcript: 'voice hello',
      );
      await tester.pumpAndSettle();

      expect(fakeTranslation.callCount, 1);
      expect(fakeTts.speakCallCount, 1);
    },
  );

  testWidgets('changing target after voice result does not auto-speak again', (
    tester,
  ) async {
    final stateKey = GlobalKey<TranslatorHomePageState>();
    final fakeTranslation = _FakeTranslationService();
    final fakeTts = _FakeTtsService();

    await _pumpTranslator(
      tester,
      key: stateKey,
      translationService: fakeTranslation,
      ttsService: fakeTts,
    );

    await stateKey.currentState!.debugCompleteVoiceSession(
      'change language',
      sessionId: 33,
    );
    await tester.pumpAndSettle();

    expect(fakeTts.speakCallCount, 1);

    await tester.tap(find.byKey(const Key('targetLanguageDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spanish').last);
    await tester.pumpAndSettle();

    expect(fakeTts.speakCallCount, 1);
    expect(find.text('change language -> es'), findsOneWidget);
  });

  testWidgets('manual speaker button still works after voice translation', (
    tester,
  ) async {
    final stateKey = GlobalKey<TranslatorHomePageState>();
    final fakeTranslation = _FakeTranslationService();
    final fakeTts = _FakeTtsService();

    await _pumpTranslator(
      tester,
      key: stateKey,
      translationService: fakeTranslation,
      ttsService: fakeTts,
    );

    await stateKey.currentState!.debugCompleteVoiceSession(
      'play manually',
      sessionId: 45,
    );
    await tester.pumpAndSettle();

    expect(fakeTts.speakCallCount, 1);
    final translatedCode = stateKey.currentState!.voiceTranslations.keys.first;
    final speakerFinder = find.byKey(Key('voice_${translatedCode}_speak'));
    final speakerButton = tester.widget<IconButton>(speakerFinder);
    expect(speakerButton.onPressed, isNotNull);
    speakerButton.onPressed!.call();
    await tester.pumpAndSettle();

    expect(fakeTts.speakCallCount, 2);
  });

  testWidgets('voice status badge covers key voice states', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: const [
              VoiceStatusBadge(state: VoicePipelineState.idle),
              VoiceStatusBadge(state: VoicePipelineState.listening),
              VoiceStatusBadge(state: VoicePipelineState.processing),
              VoiceStatusBadge(state: VoicePipelineState.success),
              VoiceStatusBadge(state: VoicePipelineState.noSpeech),
              VoiceStatusBadge(state: VoicePipelineState.error),
              VoiceStatusBadge(state: VoicePipelineState.recovering),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('Processing'), findsOneWidget);
    expect(find.text('Translated'), findsOneWidget);
    expect(find.text('No speech'), findsOneWidget);
    expect(find.text('Error'), findsOneWidget);
    expect(find.text('Recovering'), findsOneWidget);
  });
}

Future<void> _pumpTranslator(
  WidgetTester tester, {
  GlobalKey<TranslatorHomePageState>? key,
  required _FakeTranslationService translationService,
  required _FakeTtsService ttsService,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TranslatorHomePage(
        key: key,
        autoInitializeSpeech: false,
        translationService: translationService,
        ttsService: ttsService,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeTranslationService implements TranslationServiceLike {
  int callCount = 0;

  @override
  Future<MultiTranslationResult> translateToTargets({
    required String text,
    required Iterable<dynamic> targets,
  }) async {
    callCount += 1;
    final translations = <String, String>{};

    for (final target in targets) {
      final code = target is TranslationLanguageLike
          ? target.code
          : target.toString();
      translations[code] = '${text.trim()} -> $code';
    }

    return MultiTranslationResult(
      detectedLanguageCode: 'en',
      detectedLanguageName: 'English',
      translations: translations,
    );
  }
}

class _FakeTtsService implements TextToSpeechServiceLike {
  int speakCallCount = 0;
  int stopCallCount = 0;
  String? lastLocale;
  final List<String> spokenTexts = <String>[];

  @override
  Future<void> configureLocale(String localeId) async {
    lastLocale = localeId;
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text) async {
    speakCallCount += 1;
    spokenTexts.add(text.trim());
  }

  @override
  Future<void> stop() async {
    stopCallCount += 1;
  }
}
