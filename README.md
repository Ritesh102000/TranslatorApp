# Translator App (Voice + Text)

Live translator built with Flutter that turns spoken input into near real-time translations and mirrors the same workflow for typed text.

## Features

- Real-time speech recognition using [`speech_to_text`](https://pub.dev/packages/speech_to_text) with support for partial results.
- Automatic language detection powered by [`translator`](https://pub.dev/packages/translator) for both microphone and text input.
- Single-target translations into the most common U.S. languages (English, Spanish, Chinese, Tagalog, Vietnamese, Arabic, French, and Korean) with tap-to-select and dedicated output cards.
- Spoken playback via [`flutter_tts`](https://pub.dev/packages/flutter_tts) that reads the translated phrase after speech input and provides tap-to-play for the selected target language.
- Offline-friendly UX with graceful error/snackbar messaging when the network or speech subsystem is unavailable.

## Prerequisites

- Flutter 3.10+ (tested with 3.41.0) and a working set of mobile toolchains.
- Microphone permission on iOS/Android.
- Internet access for the translation API.

## Run it

```bash
flutter pub get
flutter run
```

- Windows users can run the commands above directly in PowerShell or Command Prompt with the standard Flutter installation in `C:\src\flutter` (or similar). No WSL is required.
- If you do switch between Windows and WSL development, run `flutter clean` before swapping so `.dart_tool/package_config.json` is regenerated for the target platform.
- When running inside WSL without Flutter installed in Linux mode, point `PATH` at a Linux Flutter SDK first (for example `export PATH=/home/royal/flutter-linux/bin:$PATH`).

## Notes

- Android: microphone permission is declared in `AndroidManifest.xml`.
- iOS: `NSMicrophoneUsageDescription` is in `Info.plist`.
- Speech translations wait for the microphone session to finish, auto-detect the spoken language, then deliver the translation (with audio playback) in the selected target language.
- The microphone uses the device/system locale automatically; you only choose the target translation language via the dropdown.
# TranslatorApp
