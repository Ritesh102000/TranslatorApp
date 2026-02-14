import 'package:flutter_tts/flutter_tts.dart';

abstract class TextToSpeechServiceLike {
  Future<void> configureLocale(String localeId);
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> dispose();
}

/// Minimal wrapper around [FlutterTts] to centralize speech playback controls.
class TextToSpeechService implements TextToSpeechServiceLike {
  TextToSpeechService() : _tts = FlutterTts();

  final FlutterTts _tts;
  String? _currentLocale;

  @override
  Future<void> configureLocale(String localeId) async {
    if (_currentLocale == localeId) {
      return;
    }
    _currentLocale = localeId;
    await _tts.setLanguage(localeId);
  }

  @override
  Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _tts.stop();
    await _tts.speak(trimmed);
  }

  @override
  Future<void> stop() => _tts.stop();

  @override
  Future<void> dispose() => _tts.stop();
}
