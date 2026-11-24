import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';

import '../../domain/entities/financial_ai_entities.dart';
import '../../domain/services/financial_classifier.dart';
import 'fasttext_binary_model.dart';
import 'fasttext_ffi_stub.dart'
    if (dart.library.ffi) 'fasttext_ffi_io.dart';
import 'rule_based_classifier.dart';
import 'taxonomy_catalog.dart';

typedef ModelBytesLoader = Future<Uint8List> Function(String assetPath);
typedef ModelJsonLoader = Future<String> Function(String assetPath);

/// Background worker isolate message protocol so UI thread NEVER blocks on model parsing or inference.
sealed class _WorkerRequest {
  final int id;
  const _WorkerRequest(this.id);
}

final class _PredictWorkerRequest extends _WorkerRequest {
  final String normalizedText;
  const _PredictWorkerRequest(super.id, this.normalizedText);
}

final class _ShutdownWorkerRequest extends _WorkerRequest {
  const _ShutdownWorkerRequest(super.id);
}

final class _WorkerInitPayload {
  final SendPort mainPort;
  final TransferableTypedData modelData;
  final String? expectedSha256;

  const _WorkerInitPayload({
    required this.mainPort,
    required this.modelData,
    this.expectedSha256,
  });
}

void _fastTextWorkerEntryPoint(_WorkerInitPayload init) {
  final commandPort = ReceivePort();
  final rawBytes = init.modelData.materialize().asUint8List();

  FastTextBinaryModel? dartModel;
  final ffiBinding = FastTextNativeFfiBinding();
  var ffiActive = false;

  try {
    dartModel = FastTextBinaryModel.parseAndVerify(
      rawBytes,
      expectedSha256: init.expectedSha256,
    );
    ffiActive = ffiBinding.initializeModel(rawBytes);
    init.mainPort.send({
      'type': 'ready',
      'port': commandPort.sendPort,
      'ffiActive': ffiActive,
      'numClasses': dartModel.numClasses,
      'temperature': dartModel.temperature,
    });
  } catch (e) {
    ffiBinding.dispose();
    init.mainPort.send({'type': 'init_error', 'error': e.toString()});
    commandPort.close();
    return;
  }

  commandPort.listen((dynamic msg) {
    if (msg is _ShutdownWorkerRequest) {
      ffiBinding.dispose();
      init.mainPort.send({'id': msg.id, 'shutdown': true});
      commandPort.close();
      return;
    }
    if (msg is _PredictWorkerRequest) {
      final sw = Stopwatch()..start();
      final model = dartModel!;
      final buckets = model.extractFeatureBuckets(msg.normalizedText);
      Float32List? probs;
      var usedNative = false;
      if (ffiActive) {
        probs = ffiBinding.predictProbs(buckets, model.numClasses);
        if (probs != null) {
          usedNative = true;
        }
      }
      probs ??= model.evaluateProbsFromBuckets(buckets);

      // Rank top-4 predictions in worker isolate to minimize message copy
      final indexed = List<int>.generate(model.numClasses, (i) => i)
        ..sort((a, b) => probs![b].compareTo(probs[a]));
      final topIndices = indexed.take(4).toList(growable: false);
      final topLabels = <String>[
        for (final idx in topIndices) model.labels[idx],
      ];
      final topProbs = <double>[
        for (final idx in topIndices) probs[idx],
      ];
      sw.stop();

      init.mainPort.send({
        'id': msg.id,
        'labels': topLabels,
        'probs': topProbs,
        'micros': sw.elapsedMicroseconds,
        'native': usedNative,
      });
    }
  });
}

/// Phase 9 & Phase 19 — Offline Vietnamese FastText Classifier:
/// - Loads quantized `vn_financial_fasttext_v1.ftq` lazily ONCE.
/// - Verifies SHA-256 integrity & header magic bytes.
/// - Runs 100% off the main UI isolate inside a dedicated persistent worker `Isolate`.
/// - Uses C++17 Android NDK `dart:ffi` (`liblifeos_fasttext.so`) when available on device,
///   or bit-identical INT8 tensor evaluation inside the worker `Isolate` on Desktop/Tests.
/// - Automatically degrades gracefully to [RuleBasedClassifier] if model file is missing or corrupt.
class FastTextClassifier implements FinancialClassifier {
  static const String defaultModelAsset =
      'assets/models/vn_financial_fasttext_v1.ftq';
  static const String defaultMetaAsset =
      'assets/models/vn_financial_fasttext_v1_meta.json';

  final String modelAssetPath;
  final String metaAssetPath;
  final ModelBytesLoader _bytesLoader;
  final ModelJsonLoader _jsonLoader;
  final RuleBasedClassifier _fallbackClassifier;
  final bool useWorkerIsolate;

  Isolate? _workerIsolate;
  ReceivePort? _mainReceivePort;
  SendPort? _workerSendPort;
  FastTextBinaryModel? _inlineModel;
  Completer<void>? _initCompleter;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests = {};
  int _nextRequestId = 1;
  bool _disposed = false;

  FinancialModelMetadata _metadata = const FinancialModelMetadata(
    modelId: 'vn_financial_fasttext_v1',
    modelVersion: '2.0.0',
    architecture:
        'FastText QAT Subword + Word Bigram (INT8 LFTQ v1)',
    sizeBytes: 0,
    sha256: '',
    numClasses: 30,
  );

  FastTextClassifier({
    this.modelAssetPath = defaultModelAsset,
    this.metaAssetPath = defaultMetaAsset,
    ModelBytesLoader? bytesLoader,
    ModelJsonLoader? jsonLoader,
    RuleBasedClassifier? fallbackClassifier,
    this.useWorkerIsolate = true,
  }) : _bytesLoader = bytesLoader ?? _defaultLoadAssetBytes,
       _jsonLoader = jsonLoader ?? rootBundle.loadString,
       _fallbackClassifier = fallbackClassifier ?? RuleBasedClassifier();

  static Future<Uint8List> _defaultLoadAssetBytes(String path) async {
    final bd = await rootBundle.load(path);
    return bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
  }

  @override
  FinancialModelMetadata get metadata => _metadata;

  @override
  Future<void> initialize() async {
    if (_disposed) {
      _disposed = false;
    }
    if (_workerSendPort != null ||
        _inlineModel != null ||
        _metadata.usingRuleFallback) {
      return;
    }
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    final completer = Completer<void>();
    _initCompleter = completer;

    try {
      String? expectedSha;
      var modelId = 'vn_financial_fasttext_v1';
      var modelVer = '1.0.0';
      var highTh = 0.78;
      var medTh = 0.52;
      var lowTh = 0.32;

      try {
        final rawJson = await _jsonLoader(metaAssetPath);
        final metaMap = jsonDecode(rawJson) as Map<String, dynamic>;
        expectedSha = metaMap['sha256'] as String?;
        modelId = (metaMap['modelId'] as String?) ?? modelId;
        modelVer = (metaMap['modelVersion'] as String?) ?? modelVer;
        final th = metaMap['thresholds'];
        if (th is Map) {
          highTh = (th['highConfidence'] as num?)?.toDouble() ?? highTh;
          medTh = (th['mediumConfidence'] as num?)?.toDouble() ?? medTh;
          lowTh = (th['lowConfidence'] as num?)?.toDouble() ?? lowTh;
        }
      } catch (_) {
        // Metadata JSON optional if raw model bytes verified via LFTQ header
      }

      final modelBytes = await _bytesLoader(modelAssetPath);

      if (!useWorkerIsolate) {
        final parsed = FastTextBinaryModel.parseAndVerify(
          modelBytes,
          expectedSha256: expectedSha,
        );
        _inlineModel = parsed;
        _metadata = FinancialModelMetadata(
          modelId: modelId,
          modelVersion: modelVer,
          architecture: 'FastText INT8 LFTQ v1 (Deterministic Test Mode)',
          sizeBytes: modelBytes.length,
          sha256: expectedSha ?? '',
          numClasses: parsed.numClasses,
          calibratedTemperature: parsed.temperature,
          highConfidenceThreshold: highTh,
          mediumConfidenceThreshold: medTh,
          lowConfidenceThreshold: lowTh,
          isLoaded: true,
          isNativeFfiActive: false,
          usingRuleFallback: false,
        );
        completer.complete();
        return;
      }

      final receivePort = ReceivePort();
      _mainReceivePort = receivePort;

      final initReady = Completer<Map<String, dynamic>>();
      receivePort.listen((dynamic message) {
        if (message is Map) {
          final map = Map<String, dynamic>.from(message);
          if (map['type'] == 'ready' || map['type'] == 'init_error') {
            if (!initReady.isCompleted) {
              initReady.complete(map);
            }
            return;
          }
          final reqId = map['id'] as int?;
          if (reqId != null) {
            final reqCompleter = _pendingRequests.remove(reqId);
            reqCompleter?.complete(map);
          }
        }
      });

      _workerIsolate = await Isolate.spawn<_WorkerInitPayload>(
        _fastTextWorkerEntryPoint,
        _WorkerInitPayload(
          mainPort: receivePort.sendPort,
          modelData: TransferableTypedData.fromList([modelBytes]),
          expectedSha256: expectedSha,
        ),
        debugName: 'LifeOS_FastText_AI_Worker',
      );

      final readyMsg = await initReady.future.timeout(
        const Duration(seconds: 5),
      );
      if (readyMsg['type'] == 'init_error') {
        throw FormatException(readyMsg['error']?.toString() ?? 'Init failed');
      }

      _workerSendPort = readyMsg['port'] as SendPort;
      final ffiActive = (readyMsg['ffiActive'] as bool?) ?? false;
      final numClasses = (readyMsg['numClasses'] as int?) ?? 30;
      final temp = (readyMsg['temperature'] as num?)?.toDouble() ?? 1.0;

      _metadata = FinancialModelMetadata(
        modelId: modelId,
        modelVersion: modelVer,
        architecture: ffiActive
            ? 'FastText C++17 NDK FFI + Worker Isolate (INT8 LFTQ v1)'
            : 'FastText Worker Isolate (INT8 LFTQ v1)',
        sizeBytes: modelBytes.length,
        sha256: expectedSha ?? '',
        numClasses: numClasses,
        calibratedTemperature: temp,
        highConfidenceThreshold: highTh,
        mediumConfidenceThreshold: medTh,
        lowConfidenceThreshold: lowTh,
        isLoaded: true,
        isNativeFfiActive: ffiActive,
        usingRuleFallback: false,
      );
      completer.complete();
    } catch (_) {
      // Missing or corrupt model file -> activate deterministic RuleBasedClassifier safely!
      _cleanupWorkerSync();
      await _fallbackClassifier.initialize();
      _metadata = FinancialModelMetadata.fallbackMetadata;
      completer.complete();
    } finally {
      _initCompleter = null;
    }
  }

  @override
  Future<ClassificationResult> classify(String normalizedText) async {
    if (_workerSendPort == null &&
        _inlineModel == null &&
        !_metadata.usingRuleFallback) {
      await initialize();
    }
    final inline = _inlineModel;
    if (inline != null) {
      final sw = Stopwatch()..start();
      final buckets = inline.extractFeatureBuckets(normalizedText);
      final probs = inline.evaluateProbsFromBuckets(buckets);
      final indexed = List<int>.generate(inline.numClasses, (i) => i)
        ..sort((a, b) => probs[b].compareTo(probs[a]));
      final preds = <CategoryPrediction>[
        for (final idx in indexed.take(4))
          CategoryPrediction(
            semanticKey: inline.labels[idx],
            suggestedDisplayName: FinancialTaxonomyCatalog.bySemanticKey(
              inline.labels[idx],
            ).suggestedDisplayNameVi,
            probability: probs[idx],
            origin: ClassifierInferenceOrigin.fastTextIsolateInt8,
          ),
      ];
      sw.stop();
      return ClassificationResult(
        predictions: preds,
        latencyMicros: sw.elapsedMicroseconds,
        modelVersion: _metadata.modelVersion,
        origin: ClassifierInferenceOrigin.fastTextIsolateInt8,
      );
    }
    if (_metadata.usingRuleFallback || _workerSendPort == null) {
      return _fallbackClassifier.classify(normalizedText);
    }

    final reqId = _nextRequestId++;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[reqId] = completer;
    _workerSendPort!.send(_PredictWorkerRequest(reqId, normalizedText));

    try {
      final resp = await completer.future.timeout(const Duration(seconds: 2));
      final rawLabels = (resp['labels'] as List<dynamic>).cast<String>();
      final rawProbs = (resp['probs'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList();
      final micros = (resp['micros'] as int?) ?? 0;
      final usedNative = (resp['native'] as bool?) ?? false;
      final origin = usedNative
          ? ClassifierInferenceOrigin.fastTextNativeFfi
          : ClassifierInferenceOrigin.fastTextIsolateInt8;

      final preds = <CategoryPrediction>[];
      for (var i = 0; i < rawLabels.length; i++) {
        final spec = FinancialTaxonomyCatalog.bySemanticKey(rawLabels[i]);
        preds.add(
          CategoryPrediction(
            semanticKey: rawLabels[i],
            suggestedDisplayName: spec.suggestedDisplayNameVi,
            probability: rawProbs[i],
            origin: origin,
          ),
        );
      }
      return ClassificationResult(
        predictions: preds,
        latencyMicros: micros,
        modelVersion: _metadata.modelVersion,
        origin: origin,
      );
    } catch (_) {
      _pendingRequests.remove(reqId);
      return _fallbackClassifier.classify(normalizedText);
    }
  }

  void _cleanupWorkerSync() {
    for (final c in _pendingRequests.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('Worker disposed'));
      }
    }
    _pendingRequests.clear();
    _workerSendPort = null;
    _inlineModel = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final port = _workerSendPort;
    if (port != null) {
      final id = _nextRequestId++;
      final c = Completer<Map<String, dynamic>>();
      _pendingRequests[id] = c;
      port.send(_ShutdownWorkerRequest(id));
      try {
        await c.future.timeout(const Duration(milliseconds: 250));
      } catch (_) {}
    }
    _cleanupWorkerSync();
    await _fallbackClassifier.dispose();
  }
}
