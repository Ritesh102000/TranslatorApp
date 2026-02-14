import '../../../services/translation_service.dart';

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
  TranslationLanguage(
    code: 'zh-cn',
    label: 'Chinese (Simplified)',
    ttsLocale: 'zh-CN',
  ),
  TranslationLanguage(
    code: 'zh-tw',
    label: 'Chinese (Traditional)',
    ttsLocale: 'zh-TW',
  ),
  TranslationLanguage(code: 'tl', label: 'Tagalog', ttsLocale: 'fil-PH'),
  TranslationLanguage(code: 'vi', label: 'Vietnamese', ttsLocale: 'vi-VN'),
  TranslationLanguage(code: 'ar', label: 'Arabic', ttsLocale: 'ar-SA'),
  TranslationLanguage(code: 'fr', label: 'French', ttsLocale: 'fr-FR'),
  TranslationLanguage(code: 'ko', label: 'Korean', ttsLocale: 'ko-KR'),
  TranslationLanguage(code: 'ru', label: 'Russian', ttsLocale: 'ru-RU'),
  TranslationLanguage(code: 'pt', label: 'Portuguese', ttsLocale: 'pt-BR'),
  TranslationLanguage(code: 'hi', label: 'Hindi', ttsLocale: 'hi-IN'),
  TranslationLanguage(code: 'ur', label: 'Urdu', ttsLocale: 'ur-PK'),
  TranslationLanguage(code: 'bn', label: 'Bengali', ttsLocale: 'bn-BD'),
  TranslationLanguage(code: 'gu', label: 'Gujarati', ttsLocale: 'gu-IN'),
  TranslationLanguage(code: 'te', label: 'Telugu', ttsLocale: 'te-IN'),
  TranslationLanguage(code: 'ja', label: 'Japanese', ttsLocale: 'ja-JP'),
  TranslationLanguage(code: 'de', label: 'German', ttsLocale: 'de-DE'),
  TranslationLanguage(code: 'ht', label: 'Haitian Creole', ttsLocale: 'ht-HT'),
  TranslationLanguage(code: 'fa', label: 'Persian (Farsi)', ttsLocale: 'fa-IR'),
];

const defaultPlaybackLanguageCode = 'en';
