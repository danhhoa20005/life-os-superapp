import 'package:equatable/equatable.dart';

/// Immutable snapshot of separated voice transcript state (`VOICE-009`).
class VoiceTranscriptState extends Equatable {
  final List<String> committedSegments;
  final String currentPartial;
  final String? finalSegment;
  final String? userEditedText;
  final String? activeSessionId;
  final int activeAttemptId;
  final int lastSequenceNumber;
  final String effectiveText;

  const VoiceTranscriptState({
    this.committedSegments = const <String>[],
    this.currentPartial = '',
    this.finalSegment,
    this.userEditedText,
    this.activeSessionId,
    this.activeAttemptId = 0,
    this.lastSequenceNumber = 0,
    this.effectiveText = '',
  });

  static const VoiceTranscriptState empty = VoiceTranscriptState();

  bool get hasAnyText => effectiveText.trim().isNotEmpty;

  bool get hasUserEdits => userEditedText != null;

  VoiceTranscriptState copyWith({
    List<String>? committedSegments,
    String? currentPartial,
    String? finalSegment,
    bool clearFinalSegment = false,
    String? userEditedText,
    bool clearUserEditedText = false,
    String? activeSessionId,
    bool clearActiveSessionId = false,
    int? activeAttemptId,
    int? lastSequenceNumber,
    String? effectiveText,
  }) {
    return VoiceTranscriptState(
      committedSegments: committedSegments ?? this.committedSegments,
      currentPartial: currentPartial ?? this.currentPartial,
      finalSegment: clearFinalSegment
          ? null
          : (finalSegment ?? this.finalSegment),
      userEditedText: clearUserEditedText
          ? null
          : (userEditedText ?? this.userEditedText),
      activeSessionId: clearActiveSessionId
          ? null
          : (activeSessionId ?? this.activeSessionId),
      activeAttemptId: activeAttemptId ?? this.activeAttemptId,
      lastSequenceNumber: lastSequenceNumber ?? this.lastSequenceNumber,
      effectiveText: effectiveText ?? this.effectiveText,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    committedSegments,
    currentPartial,
    finalSegment,
    userEditedText,
    activeSessionId,
    activeAttemptId,
    lastSequenceNumber,
    effectiveText,
  ];
}
