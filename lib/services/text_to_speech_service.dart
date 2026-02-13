import 'package:flutter_tts/flutter_tts.dart';

/// Minimal wrapper around [FlutterTts] to centralize speech playback controls.
class TextToSpeechService {
  TextToSpeechService() : _tts = FlutterTts();

  final FlutterTts _tts;
  String? _currentLocale;

  Future<void> configureLocale(String localeId) async {
    if (_currentLocale == localeId) {
      return;
    }
    _currentLocale = localeId;
    await _tts.setLanguage(localeId);
  }

  Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _tts.stop();
    await _tts.speak(trimmed);
  }

  Future<void> stop() => _tts.stop();

  Future<void> dispose() => _tts.stop();
}
