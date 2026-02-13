import 'dart:collection';

import 'package:translator/translator.dart';

/// Coordinates calls to the GoogleTranslator client, automatically detecting
/// the input language and translating it to the requested targets.
class TranslationService {
  TranslationService({GoogleTranslator? client})
      : _client = client ?? GoogleTranslator();

  final GoogleTranslator _client;
  final _cache = HashMap<_TranslationKey, _CachedTranslation>();

  Future<MultiTranslationResult> translateToTargets({
    required String text,
    required Iterable<dynamic> targets,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return const MultiTranslationResult.empty();
    }

    try {
      final futures = targets
          .map((target) => _translateSingle(normalized, _targetCode(target)))
          .toList(growable: false);
      final responses = await Future.wait(futures);
      final translations = <String, String>{};
      String? detectedCode;
      String? detectedName;

      for (final response in responses) {
        translations[response.targetCode] = response.text;
        detectedCode ??= response.detectedCode;
        detectedName ??= response.detectedName;
      }

      return MultiTranslationResult(
        detectedLanguageCode: detectedCode,
        detectedLanguageName: detectedName,
        translations: translations,
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        TranslationException(error.toString()),
        stackTrace,
      );
    }
  }

  Future<_TranslationResponse> _translateSingle(
    String text,
    String targetCode,
  ) async {
    final key = _TranslationKey(text, 'auto', targetCode);
    final cached = _cache[key];
    if (cached != null) {
      return _TranslationResponse(
        targetCode: targetCode,
        text: cached.translation,
        detectedCode: cached.detectedCode,
        detectedName: cached.detectedName,
      );
    }

    final translation = await _client.translate(
      text,
      from: 'auto',
      to: targetCode,
    );
    final trimmed = translation.text.trim();
    final detectedCode = translation.sourceLanguage.code;
    final detectedName = translation.sourceLanguage.name;
    _cache[key] = _CachedTranslation(
      translation: trimmed,
      detectedCode: detectedCode,
      detectedName: detectedName,
    );

    return _TranslationResponse(
      targetCode: targetCode,
      text: trimmed,
      detectedCode: detectedCode,
      detectedName: detectedName,
    );
  }

  String _targetCode(dynamic target) {
    if (target is String) {
      return target;
    }
    if (target is TranslationLanguageLike) {
      return target.code;
    }
    throw ArgumentError('Unsupported translation target type: $target');
  }
}

abstract class TranslationLanguageLike {
  String get code;
}

class MultiTranslationResult {
  const MultiTranslationResult({
    required this.detectedLanguageCode,
    required this.detectedLanguageName,
    required this.translations,
  });

  const MultiTranslationResult.empty()
      : detectedLanguageCode = null,
        detectedLanguageName = null,
        translations = const {};

  final String? detectedLanguageCode;
  final String? detectedLanguageName;
  final Map<String, String> translations;
}

class TranslationException implements Exception {
  const TranslationException(this.message);
  final String message;

  @override
  String toString() => 'TranslationException: $message';
}

class _TranslationKey {
  const _TranslationKey(this.text, this.from, this.to);
  final String text;
  final String from;
  final String to;

  @override
  bool operator ==(Object other) {
    return other is _TranslationKey &&
        other.text == text &&
        other.from == from &&
        other.to == to;
  }

  @override
  int get hashCode => Object.hash(text, from, to);
}

class _CachedTranslation {
  const _CachedTranslation({
    required this.translation,
    required this.detectedCode,
    required this.detectedName,
  });

  final String translation;
  final String detectedCode;
  final String detectedName;
}

class _TranslationResponse {
  const _TranslationResponse({
    required this.targetCode,
    required this.text,
    required this.detectedCode,
    required this.detectedName,
  });

  final String targetCode;
  final String text;
  final String detectedCode;
  final String detectedName;
}
