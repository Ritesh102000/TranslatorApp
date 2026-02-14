import 'package:flutter/material.dart';

import '../models/voice_pipeline_state.dart';

class VoiceStatusBadge extends StatelessWidget {
  const VoiceStatusBadge({super.key, required this.state, this.message});

  final VoicePipelineState state;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = _colorForState(state, colorScheme);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(_iconForState(state), color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message ?? state.defaultMessage,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            state.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: iconColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForState(VoicePipelineState state) {
    switch (state) {
      case VoicePipelineState.idle:
        return Icons.mic_none_rounded;
      case VoicePipelineState.listening:
        return Icons.graphic_eq_rounded;
      case VoicePipelineState.processing:
        return Icons.hourglass_top_rounded;
      case VoicePipelineState.success:
        return Icons.check_circle_rounded;
      case VoicePipelineState.noSpeech:
        return Icons.record_voice_over_rounded;
      case VoicePipelineState.error:
        return Icons.error_rounded;
      case VoicePipelineState.recovering:
        return Icons.autorenew_rounded;
    }
  }

  Color _colorForState(VoicePipelineState state, ColorScheme colorScheme) {
    switch (state) {
      case VoicePipelineState.idle:
        return colorScheme.primary;
      case VoicePipelineState.listening:
        return colorScheme.primary;
      case VoicePipelineState.processing:
        return colorScheme.tertiary;
      case VoicePipelineState.success:
        return Colors.green.shade700;
      case VoicePipelineState.noSpeech:
        return colorScheme.secondary;
      case VoicePipelineState.error:
        return colorScheme.error;
      case VoicePipelineState.recovering:
        return colorScheme.tertiary;
    }
  }
}
