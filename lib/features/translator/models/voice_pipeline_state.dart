enum VoicePipelineState {
  idle,
  listening,
  processing,
  success,
  noSpeech,
  error,
  recovering,
}

extension VoicePipelineStateX on VoicePipelineState {
  String get label {
    switch (this) {
      case VoicePipelineState.idle:
        return 'Ready';
      case VoicePipelineState.listening:
        return 'Listening';
      case VoicePipelineState.processing:
        return 'Processing';
      case VoicePipelineState.success:
        return 'Translated';
      case VoicePipelineState.noSpeech:
        return 'No speech';
      case VoicePipelineState.error:
        return 'Error';
      case VoicePipelineState.recovering:
        return 'Recovering';
    }
  }

  String get defaultMessage {
    switch (this) {
      case VoicePipelineState.idle:
        return 'Tap the microphone and start speaking.';
      case VoicePipelineState.listening:
        return 'Listening for your speech...';
      case VoicePipelineState.processing:
        return 'Detecting language and translating...';
      case VoicePipelineState.success:
        return 'Translation ready.';
      case VoicePipelineState.noSpeech:
        return 'No speech detected. Tap the mic and speak right away.';
      case VoicePipelineState.error:
        return 'Voice translation failed. Try again.';
      case VoicePipelineState.recovering:
        return 'Speech service disconnected. Reconnecting...';
    }
  }

  bool get isBusy {
    return this == VoicePipelineState.listening ||
        this == VoicePipelineState.processing ||
        this == VoicePipelineState.recovering;
  }
}
