import 'dart:typed_data';

/// Web/non-FFI stub when `dart:ffi` is unavailable (e.g. Chrome Web builds).
class FastTextNativeFfiBinding {
  bool get isSupportedAndLoaded => false;

  bool initializeModel(Uint8List modelBytes) => false;

  Float32List? predictProbs(List<int> bucketIds, int numClasses) => null;

  void dispose() {}
}
