import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../services/text_to_speech_service.dart';
import '../../services/translation_service.dart';
import 'models/translation_language.dart';
import 'models/voice_pipeline_state.dart';
import 'widgets/section_card.dart';
import 'widgets/translation_language_selector.dart';
import 'widgets/translation_results.dart';
import 'widgets/voice_status_badge.dart';

class TranslatorHomePage extends StatefulWidget {
  const TranslatorHomePage({
    super.key,
    this.translationService,
    this.speechClient,
    this.ttsService,
    this.micRecorder,
    this.autoInitializeSpeech = true,
  });

  final TranslationServiceLike? translationService;
  final SpeechToText? speechClient;
  final TextToSpeechServiceLike? ttsService;
  final AudioRecorder? micRecorder;
  final bool autoInitializeSpeech;

  @override
  State<TranslatorHomePage> createState() => TranslatorHomePageState();
}

class TranslatorHomePageState extends State<TranslatorHomePage> {
  static const _audioInputChannel = MethodChannel('translator_app/audio_input');
  static const _minDbForMeter = -50.0;

  late final SpeechToText speechToText;
  late final AudioRecorder micTesterRecorder;
  late final TranslationServiceLike translationService;
  late final TextToSpeechServiceLike ttsService;
  final textController = TextEditingController();

  String? speechLocaleId;

  VoicePipelineState voiceState = VoicePipelineState.idle;
  bool isListening = false;
  bool speechReady = false;
  bool textTranslating = false;
  bool speechServiceRecovering = false;
  String? voiceStateOverrideMessage;

  String voiceTranscript = '';
  String? textDetectedLanguage;
  String? voiceDetectedLanguage;
  bool heardSpeechInCurrentSession = false;

  bool micTesterActive = false;
  double micTesterCurrentDb = _minDbForMeter;
  double micTesterPeakDb = _minDbForMeter;
  String micTesterStatus = 'Tap Start to test raw microphone input.';

  Map<String, String> textTranslations = {};
  Map<String, String> voiceTranslations = {};
  TranslationLanguage selectedTarget = translationTargets.first;

  Timer? textDebounce;
  StreamSubscription<Amplitude>? micAmplitudeSubscription;
  int textRequestId = 0;
  int voiceRequestId = 0;
  int voiceSessionId = 0;
  int? activeVoiceSessionId;
  final Set<int> _translatedVoiceSessionIds = <int>{};

  @override
  void initState() {
    super.initState();
    speechToText = widget.speechClient ?? SpeechToText();
    micTesterRecorder = widget.micRecorder ?? AudioRecorder();
    translationService = widget.translationService ?? TranslationService();
    ttsService = widget.ttsService ?? TextToSpeechService();

    if (widget.autoInitializeSpeech) {
      unawaited(_initSpeech());
    }
  }

  List<TranslationLanguage> get activeTranslationTargets => [selectedTarget];

  String get _voiceMessage =>
      voiceStateOverrideMessage ?? voiceState.defaultMessage;

  @visibleForTesting
  Future<void> debugCompleteVoiceSession(
    String transcript, {
    int? sessionId,
  }) async {
    final normalized = transcript.trim();
    final resolvedSessionId = sessionId ?? ++voiceSessionId;
    if (mounted) {
      setState(() {
        voiceTranscript = normalized;
        isListening = false;
        activeVoiceSessionId = null;
      });
    }
    await _processFinalVoiceTranscript(
      transcript: normalized,
      sessionId: resolvedSessionId,
      autoSpeak: true,
    );
  }

  @visibleForTesting
  Future<void> debugEmitFinalVoiceResult({
    required int sessionId,
    required String transcript,
  }) async {
    await _processFinalVoiceTranscript(
      transcript: transcript,
      sessionId: sessionId,
      autoSpeak: true,
    );
  }

  Future<void> _initSpeech() async {
    try {
      final available = await speechToText.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
        debugLogging: kDebugMode,
        options: [
          SpeechToText.androidNoBluetooth,
          SpeechToText.androidIntentLookup,
        ],
      );
      if (!mounted) {
        return;
      }
      final systemLocale = available ? await speechToText.systemLocale() : null;
      if (!mounted) {
        return;
      }
      setState(() {
        speechReady = available;
        speechLocaleId = systemLocale?.localeId ?? speechLocaleId ?? 'en_US';
        if (available &&
            voiceState == VoicePipelineState.error &&
            !isListening) {
          voiceState = VoicePipelineState.idle;
          voiceStateOverrideMessage = null;
        }
      });
      if (!available) {
        _setVoiceState(
          VoicePipelineState.error,
          message: 'Speech recognition is not available on this device.',
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        speechReady = false;
        speechLocaleId ??= 'en_US';
      });
      _setVoiceState(
        VoicePipelineState.error,
        message: 'Could not initialize speech recognition.',
      );
    }
  }

  void _setVoiceState(VoicePipelineState state, {String? message}) {
    if (!mounted) {
      return;
    }
    setState(() {
      voiceState = state;
      voiceStateOverrideMessage = message;
    });
  }

  Future<void> _toggleListening() async {
    if (isListening) {
      await _stopListening(manualStop: true);
      return;
    }

    await _startListening();
  }

  Future<void> _startListening() async {
    if (speechServiceRecovering) {
      return;
    }

    if (!speechReady) {
      await _initSpeech();
    }
    if (!speechReady) {
      _setVoiceState(
        VoicePipelineState.error,
        message: 'Speech recognition is not available.',
      );
      _showError('Speech recognition is not available on this device.');
      return;
    }

    var hasPermission = await speechToText.hasPermission;
    if (!hasPermission) {
      await _initSpeech();
      hasPermission = await speechToText.hasPermission;
    }
    if (!hasPermission) {
      _setVoiceState(
        VoicePipelineState.error,
        message: 'Microphone permission is required in app settings.',
      );
      _showError(
        'Microphone permission is required. Enable it in app settings.',
      );
      return;
    }

    if (micTesterActive) {
      await _stopMicTester();
    }

    await ttsService.stop();
    try {
      await speechToText.cancel();
    } catch (_) {
      // Continue to listen setup even if cancel fails.
    }

    final sessionId = ++voiceSessionId;
    activeVoiceSessionId = sessionId;
    voiceRequestId++;
    heardSpeechInCurrentSession = false;
    _translatedVoiceSessionIds.removeWhere((id) => id < sessionId - 8);

    setState(() {
      isListening = true;
      voiceTranscript = '';
      voiceTranslations = {};
      voiceDetectedLanguage = null;
      voiceState = VoicePipelineState.listening;
      voiceStateOverrideMessage = null;
    });

    final localeId = await _resolveSpeechLocaleId();
    try {
      await _prepareAudioInputPath();
      await speechToText.listen(
        localeId: localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        onResult: (result) => _handleSpeechResult(result, sessionId),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (error) {
      if (!mounted || activeVoiceSessionId != sessionId) {
        return;
      }
      setState(() {
        isListening = false;
        activeVoiceSessionId = null;
      });
      _setVoiceState(
        VoicePipelineState.error,
        message: 'Could not start voice input.',
      );
      _showError('Could not start voice input: $error');
    }
  }

  Future<void> _stopListening({required bool manualStop}) async {
    final sessionId = activeVoiceSessionId;
    try {
      await speechToText.stop();
    } catch (_) {
      // Best effort stop.
    }

    if (!mounted) {
      return;
    }

    setState(() {
      isListening = false;
      activeVoiceSessionId = null;
    });

    final transcript = voiceTranscript.trim();
    if (manualStop && transcript.isNotEmpty) {
      await _processFinalVoiceTranscript(
        transcript: transcript,
        sessionId: sessionId ?? voiceSessionId,
        autoSpeak: true,
      );
      return;
    }

    if (manualStop && voiceState == VoicePipelineState.listening) {
      _setVoiceState(VoicePipelineState.idle);
    }
  }

  void _handleSpeechResult(SpeechRecognitionResult result, int sessionId) {
    if (activeVoiceSessionId != sessionId) {
      return;
    }

    final recognized = result.recognizedWords.trim();
    if (recognized.isNotEmpty) {
      heardSpeechInCurrentSession = true;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      if (recognized.isNotEmpty) {
        voiceTranscript = recognized;
      }
      if (result.finalResult) {
        isListening = false;
        voiceState = VoicePipelineState.processing;
        voiceStateOverrideMessage = null;
      } else {
        voiceState = VoicePipelineState.listening;
        voiceStateOverrideMessage = null;
      }
    });

    if (result.finalResult) {
      final finalTranscript = recognized.isEmpty
          ? voiceTranscript.trim()
          : recognized;
      unawaited(
        _processFinalVoiceTranscript(
          transcript: finalTranscript,
          sessionId: sessionId,
          autoSpeak: true,
        ),
      );
    }
  }

  Future<void> _processFinalVoiceTranscript({
    required String transcript,
    required int sessionId,
    required bool autoSpeak,
  }) async {
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) {
      _setVoiceState(VoicePipelineState.noSpeech);
      return;
    }

    if (_translatedVoiceSessionIds.contains(sessionId)) {
      return;
    }

    _translatedVoiceSessionIds.add(sessionId);
    _setVoiceState(VoicePipelineState.processing);
    await _translateVoice(trimmed, sessionId: sessionId, autoSpeak: autoSpeak);
  }

  Future<void> _translateVoice(
    String value, {
    required int sessionId,
    bool autoSpeak = false,
  }) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        voiceTranslations = {};
        voiceDetectedLanguage = null;
      });
      _setVoiceState(VoicePipelineState.noSpeech);
      await ttsService.stop();
      return;
    }

    final currentRequest = ++voiceRequestId;
    _setVoiceState(VoicePipelineState.processing);
    final targets = activeTranslationTargets;
    if (targets.isEmpty) {
      _setVoiceState(
        VoicePipelineState.error,
        message: 'Select at least one target language.',
      );
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
      if (activeVoiceSessionId != null && activeVoiceSessionId != sessionId) {
        return;
      }

      setState(() {
        voiceTranslations = result.translations;
        voiceDetectedLanguage = result.detectedLanguageName;
        activeVoiceSessionId = null;
      });
      _setVoiceState(VoicePipelineState.success);
      if (autoSpeak) {
        await _speakPrimaryTranslation(result.translations);
      }
    } catch (_) {
      if (!mounted || currentRequest != voiceRequestId) {
        return;
      }
      setState(() => activeVoiceSessionId = null);
      _setVoiceState(
        VoicePipelineState.error,
        message: 'Unable to translate voice input. Please try again.',
      );
      _showError('Unable to translate voice input. Please try again.');
    }
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) {
      return;
    }
    if (status == 'notListening') {
      setState(() => isListening = false);
      if (voiceState == VoicePipelineState.listening) {
        final noSpeechDetected =
            voiceTranscript.trim().isEmpty && !heardSpeechInCurrentSession;
        _setVoiceState(
          noSpeechDetected
              ? VoicePipelineState.noSpeech
              : VoicePipelineState.idle,
        );
      }
    }
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    if (!mounted) {
      return;
    }

    final normalizedError = error.errorMsg.trim().toLowerCase();
    if (_isServerDisconnectedError(normalizedError)) {
      unawaited(_recoverSpeechService());
      return;
    }
    if (_isNoSpeechError(normalizedError)) {
      setState(() {
        isListening = false;
        activeVoiceSessionId = null;
      });
      _setVoiceState(VoicePipelineState.noSpeech);
      return;
    }

    setState(() {
      isListening = false;
      activeVoiceSessionId = null;
    });
    final message = error.permanent
        ? 'Speech service unavailable. Check speech services and retry.'
        : 'Speech input failed. Retry after a second.';
    _setVoiceState(VoicePipelineState.error, message: message);
    _showError('Speech error: ${error.errorMsg}');
  }

  bool _isNoSpeechError(String normalizedError) {
    return normalizedError.contains('error_speech_timeout') ||
        normalizedError.contains('error_no_match');
  }

  bool _isServerDisconnectedError(String normalizedError) {
    return normalizedError.contains('error_server_disconnected');
  }

  Future<void> _recoverSpeechService() async {
    if (speechServiceRecovering || !mounted) {
      return;
    }
    speechServiceRecovering = true;

    setState(() {
      isListening = false;
      activeVoiceSessionId = null;
    });
    _setVoiceState(VoicePipelineState.recovering);

    try {
      try {
        await speechToText.cancel();
      } catch (_) {
        // Continue recovery.
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _initSpeech();
      if (!mounted) {
        return;
      }
      if (speechReady) {
        _setVoiceState(
          VoicePipelineState.idle,
          message: 'Speech reconnected. Tap mic to continue.',
        );
      } else {
        _setVoiceState(
          VoicePipelineState.error,
          message: 'Speech service unavailable. Check Google speech services.',
        );
        _showError(
          'Speech service unavailable. Update/enable Google app and Speech Services by Google.',
        );
      }
    } finally {
      speechServiceRecovering = false;
    }
  }

  Future<void> _prepareAudioInputPath() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _audioInputChannel.invokeMethod<void>('useBuiltInMic');
    } catch (_) {
      // Best-effort route adjustment.
    }
  }

  Future<String?> _resolveSpeechLocaleId() async {
    final fallbackLocaleId = speechLocaleId ?? 'en_US';
    try {
      final locales = await speechToText.locales();
      if (locales.isEmpty) {
        return null;
      }

      final exactMatch = locales
          .where((locale) => locale.localeId == fallbackLocaleId)
          .map((locale) => locale.localeId)
          .cast<String?>()
          .firstWhere((_) => true, orElse: () => null);

      final fallbackLanguage = fallbackLocaleId.split(RegExp('[_-]')).first;
      final languageMatch = locales
          .where(
            (locale) =>
                locale.localeId.toLowerCase().startsWith(
                  '${fallbackLanguage.toLowerCase()}_',
                ) ||
                locale.localeId.toLowerCase().startsWith(
                  '${fallbackLanguage.toLowerCase()}-',
                ),
          )
          .map((locale) => locale.localeId)
          .cast<String?>()
          .firstWhere((_) => true, orElse: () => null);

      final resolvedLocaleId = exactMatch ?? languageMatch;
      if (mounted && resolvedLocaleId != speechLocaleId) {
        setState(() => speechLocaleId = resolvedLocaleId);
      }
      return resolvedLocaleId;
    } catch (_) {
      return null;
    }
  }

  double _dbToMeterValue(double db) {
    final safeDb = db.isFinite ? db : _minDbForMeter;
    final clampedDb = safeDb.clamp(_minDbForMeter, 0.0).toDouble();
    return (clampedDb - _minDbForMeter) / (0 - _minDbForMeter);
  }

  Future<void> _toggleMicTester() async {
    if (micTesterActive) {
      await _stopMicTester();
      return;
    }
    await _startMicTester();
  }

  Future<void> _startMicTester() async {
    try {
      final hasPermission = await micTesterRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) {
          return;
        }
        setState(() {
          micTesterActive = false;
          micTesterStatus = 'Microphone permission denied for mic tester.';
        });
        _showError('Microphone permission denied for mic tester.');
        return;
      }

      await ttsService.stop();
      if (isListening) {
        await _stopListening(manualStop: false);
      }

      await _prepareAudioInputPath();
      await micTesterRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );

      await micAmplitudeSubscription?.cancel();
      micAmplitudeSubscription = micTesterRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((amplitude) {
            if (!mounted) {
              return;
            }
            final currentDb = amplitude.current.isFinite
                ? amplitude.current
                : _minDbForMeter;
            final peakDb = amplitude.max.isFinite ? amplitude.max : currentDb;
            setState(() {
              micTesterCurrentDb = currentDb;
              if (peakDb > micTesterPeakDb) {
                micTesterPeakDb = peakDb;
              }
            });
          });

      if (!mounted) {
        return;
      }
      setState(() {
        micTesterActive = true;
        micTesterCurrentDb = _minDbForMeter;
        micTesterPeakDb = _minDbForMeter;
        micTesterStatus = 'Recording raw mic audio... speak now.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        micTesterActive = false;
        micTesterStatus = 'Mic tester could not start.';
      });
      _showError('Mic tester start failed: $error');
    }
  }

  Future<void> _stopMicTester() async {
    await micAmplitudeSubscription?.cancel();
    micAmplitudeSubscription = null;
    try {
      await micTesterRecorder.stop();
    } catch (_) {
      // Ignore stop errors on inactive sessions.
    }
    if (!mounted) {
      return;
    }
    setState(() {
      micTesterActive = false;
      micTesterStatus =
          'Mic tester stopped. Peak: ${micTesterPeakDb.toStringAsFixed(1)} dB';
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
      if (!mounted) {
        return;
      }
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
    } catch (_) {
      if (!mounted || currentRequest != textRequestId) {
        return;
      }
      _showError('Unable to translate text input. Check your connection.');
      setState(() => textTranslating = false);
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
      ),
    );
  }

  void _handleTargetSelection(String code) {
    final language = translationTargets.firstWhere(
      (item) => item.code == code,
      orElse: () => translationTargets.first,
    );
    setState(() {
      selectedTarget = language;
    });
    _rerunActiveTranslations();
  }

  void _rerunActiveTranslations() {
    final typed = textController.text.trim();
    if (typed.isNotEmpty) {
      unawaited(_translateTyped(typed));
    }

    final spoken = voiceTranscript.trim();
    if (spoken.isNotEmpty && !isListening) {
      unawaited(
        _translateVoice(spoken, sessionId: voiceSessionId, autoSpeak: false),
      );
    }
  }

  Future<void> _speakPrimaryTranslation(
    Map<String, String> translations,
  ) async {
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
  void dispose() {
    textDebounce?.cancel();
    micAmplitudeSubscription?.cancel();
    textController.dispose();
    unawaited(speechToText.stop());
    unawaited(micTesterRecorder.dispose());
    unawaited(ttsService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF4FBFF),
              const Color(0xFFE9F7F2),
              const Color(0xFFF8F4EA),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 760;
              final horizontalPadding = wide
                  ? ((constraints.maxWidth - 700) / 2).clamp(20.0, 120.0)
                  : 16.0;

              return ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  16,
                  horizontalPadding,
                  24,
                ),
                children: [
                  Text(
                    'Live Voice Translator',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap mic, speak naturally, and get automatic language detection with instant translation.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Language Setup',
                    subtitle: 'Choose the language you want to hear and read.',
                    child: TranslationLanguageSelector(
                      targets: translationTargets,
                      selectedTarget: selectedTarget,
                      onChanged: _handleTargetSelection,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Speak to Translate',
                    subtitle:
                        'Single-tap voice flow with automatic language detection.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        VoiceStatusBadge(
                          state: voiceState,
                          message: _voiceMessage,
                        ),
                        const SizedBox(height: 14),
                        Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: isListening
                                    ? [
                                        colorScheme.primary,
                                        colorScheme.tertiary,
                                      ]
                                    : [
                                        colorScheme.primaryContainer,
                                        colorScheme.secondaryContainer,
                                      ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.25,
                                  ),
                                  blurRadius: isListening ? 30 : 16,
                                  spreadRadius: isListening ? 2 : 0,
                                ),
                              ],
                            ),
                            child: IconButton(
                              iconSize: 40,
                              color: colorScheme.onPrimary,
                              onPressed: _toggleListening,
                              icon: Icon(
                                isListening
                                    ? Icons.stop_rounded
                                    : Icons.mic_rounded,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: Text(
                            isListening ? 'Tap to stop' : 'Tap to speak',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Transcript',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(minHeight: 92),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          child: Text(
                            voiceTranscript.isEmpty
                                ? 'Your live transcript appears here.'
                                : voiceTranscript,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TranslationResults(
                          translations: voiceTranslations,
                          targets: activeTranslationTargets,
                          detectedLanguage: voiceDetectedLanguage,
                          isLoading:
                              voiceState == VoicePipelineState.processing,
                          emptyMessage:
                              'Speak first to see translation output.',
                          speakerKeyPrefix: 'voice',
                          onSpeak: _speakText,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Type to Translate',
                    subtitle:
                        'Fast keyboard fallback with the same target language.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          key: const Key('typedInputField'),
                          controller: textController,
                          maxLines: null,
                          onChanged: _onTypedText,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Source text',
                            hintText: 'Start typing to translate instantly',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TranslationResults(
                          translations: textTranslations,
                          targets: activeTranslationTargets,
                          detectedLanguage: textDetectedLanguage,
                          isLoading: textTranslating,
                          speakerKeyPrefix: 'typed',
                          onSpeak: _speakText,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Diagnostics',
                    subtitle:
                        'Optional microphone-level tester for troubleshooting only.',
                    child: Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        title: Text(
                          'Mic tester (no speech recognition)',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        children: [
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  micTesterStatus,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _toggleMicTester,
                                icon: Icon(
                                  micTesterActive
                                      ? Icons.stop_circle_outlined
                                      : Icons.mic_none_rounded,
                                ),
                                label: Text(micTesterActive ? 'Stop' : 'Start'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: _dbToMeterValue(micTesterCurrentDb),
                            minHeight: 9,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Current: ${micTesterCurrentDb.toStringAsFixed(1)} dBFS | Peak: ${micTesterPeakDb.toStringAsFixed(1)} dBFS',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
