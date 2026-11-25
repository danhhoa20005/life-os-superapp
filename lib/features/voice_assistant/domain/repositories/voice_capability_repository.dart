import '../entities/voice_engine_capability.dart';
import '../services/engine_selection_policy.dart';

/// Persistent capability memory repository scoped to device SDK/OS/service/locale/route.
abstract interface class VoiceCapabilityRepository {
  Future<List<VoiceEngineCapabilityEntry>> loadEntries();

  Future<void> upsertEntry(VoiceEngineCapabilityEntry entry);

  Future<void> recordSuccess({
    required VoiceEngineId engineId,
    required VoiceEnvironmentSnapshot environment,
  });

  Future<void> recordError({
    required VoiceEngineId engineId,
    required VoiceEnvironmentSnapshot environment,
    required String? errorCode,
    bool? stillAvailable,
    bool? stillSupportsVietnamese,
  });

  Future<void> clearAll();
}
