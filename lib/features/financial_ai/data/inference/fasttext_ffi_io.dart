import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

typedef _AllocNative = ffi.Pointer<ffi.Uint8> Function(ffi.Int32 byteLen);
typedef _AllocDart = ffi.Pointer<ffi.Uint8> Function(int byteLen);

typedef _DeallocNative = ffi.Void Function(ffi.Pointer<ffi.Void> ptr);
typedef _DeallocDart = void Function(ffi.Pointer<ffi.Void> ptr);

typedef _CreateNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Uint8> data,
      ffi.Int32 byteLen,
    );
typedef _CreateDart =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint8> data, int byteLen);

typedef _PredictNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void> handle,
      ffi.Pointer<ffi.Uint32> bucketIds,
      ffi.Int32 bucketCount,
      ffi.Pointer<ffi.Float> outProbs,
      ffi.Int32 outLen,
    );
typedef _PredictDart =
    int Function(
      ffi.Pointer<ffi.Void> handle,
      ffi.Pointer<ffi.Uint32> bucketIds,
      int bucketCount,
      ffi.Pointer<ffi.Float> outProbs,
      int outLen,
    );

typedef _DestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void> handle);
typedef _DestroyDart = void Function(ffi.Pointer<ffi.Void> handle);

/// Native C++17 `dart:ffi` bridge to `liblifeos_fasttext.so` (Android NDK) / iOS static symbol.
/// Manages native heap lifecycle deterministically with zero leaks.
class FastTextNativeFfiBinding {
  ffi.DynamicLibrary? _lib;
  _AllocDart? _alloc;
  _DeallocDart? _dealloc;
  _CreateDart? _create;
  _PredictDart? _predict;
  _DestroyDart? _destroy;
  ffi.Pointer<ffi.Void> _modelHandle = ffi.nullptr;

  bool get isSupportedAndLoaded =>
      _modelHandle != ffi.nullptr && _predict != null;

  bool _ensureLibraryOpened() {
    if (_lib != null) return true;
    try {
      if (Platform.isAndroid) {
        _lib = ffi.DynamicLibrary.open('liblifeos_fasttext.so');
      } else if (Platform.isIOS) {
        _lib = ffi.DynamicLibrary.process();
      } else {
        return false;
      }
      _alloc = _lib!.lookupFunction<_AllocNative, _AllocDart>(
        'lifeos_ftx_alloc',
      );
      _dealloc = _lib!.lookupFunction<_DeallocNative, _DeallocDart>(
        'lifeos_ftx_dealloc',
      );
      _create = _lib!.lookupFunction<_CreateNative, _CreateDart>(
        'lifeos_ftx_create',
      );
      _predict = _lib!.lookupFunction<_PredictNative, _PredictDart>(
        'lifeos_ftx_predict',
      );
      _destroy = _lib!.lookupFunction<_DestroyNative, _DestroyDart>(
        'lifeos_ftx_destroy',
      );
      return true;
    } catch (_) {
      _lib = null;
      return false;
    }
  }

  bool initializeModel(Uint8List modelBytes) {
    dispose();
    if (modelBytes.isEmpty || !_ensureLibraryOpened()) {
      return false;
    }
    final buf = _alloc!(modelBytes.length);
    if (buf == ffi.nullptr) return false;
    try {
      buf.asTypedList(modelBytes.length).setAll(0, modelBytes);
      final handle = _create!(buf, modelBytes.length);
      if (handle == ffi.nullptr) {
        return false;
      }
      _modelHandle = handle;
      return true;
    } finally {
      _dealloc!(buf.cast<ffi.Void>());
    }
  }

  Float32List? predictProbs(List<int> bucketIds, int numClasses) {
    if (!isSupportedAndLoaded || numClasses <= 0) return null;
    final count = bucketIds.length;
    final inBytes = (count > 0 ? count : 1) * 4;
    final outBytes = numClasses * 4;

    final inPtr = _alloc!(inBytes).cast<ffi.Uint32>();
    final outPtr = _alloc!(outBytes).cast<ffi.Float>();
    if (inPtr == ffi.nullptr || outPtr == ffi.nullptr) {
      if (inPtr != ffi.nullptr) _dealloc!(inPtr.cast<ffi.Void>());
      if (outPtr != ffi.nullptr) _dealloc!(outPtr.cast<ffi.Void>());
      return null;
    }

    try {
      if (count > 0) {
        final inList = inPtr.asTypedList(count);
        for (var i = 0; i < count; i++) {
          inList[i] = bucketIds[i];
        }
      }
      final rc = _predict!(
        _modelHandle,
        count > 0 ? inPtr : ffi.nullptr,
        count,
        outPtr,
        numClasses,
      );
      if (rc != 0) return null;
      return Float32List.fromList(outPtr.asTypedList(numClasses));
    } finally {
      _dealloc!(inPtr.cast<ffi.Void>());
      _dealloc!(outPtr.cast<ffi.Void>());
    }
  }

  void dispose() {
    if (_modelHandle != ffi.nullptr && _destroy != null) {
      _destroy!(_modelHandle);
    }
    _modelHandle = ffi.nullptr;
  }
}
