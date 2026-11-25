import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import '../normalization/financial_text_normalizer.dart';

/// Bit-identical `LFTQ` v1 quantized FastText binary model parser & evaluator.
/// Validates magic header, bounds, and optional SHA-256 checksum so corrupt/truncated
/// model files fail cleanly without crashing or corrupting memory.
class FastTextBinaryModel {
  static const String oodLabel = '__ood__';

  final int version;

  /// Number of in-domain semantic classes (excluding optional `__ood__` rejection label).
  /// Use [totalClasses] for the raw `LFTQ` output tensor length.
  final int numClasses;
  final int totalClasses;
  final int dim;
  final int numBuckets;
  final int wordNgrams;
  final int minSubword;
  final int maxSubword;
  final double temperature;
  final List<String> labels;
  final int oodClassIndex;
  final Float32List scalesA;
  final Int8List weightsA;
  final Float32List weightsW;
  final Float32List biasB;

  const FastTextBinaryModel._({
    required this.version,
    required this.numClasses,
    required this.totalClasses,
    required this.dim,
    required this.numBuckets,
    required this.wordNgrams,
    required this.minSubword,
    required this.maxSubword,
    required this.temperature,
    required this.labels,
    required this.oodClassIndex,
    required this.scalesA,
    required this.weightsA,
    required this.weightsW,
    required this.biasB,
  });

  bool get hasExplicitOodClass => oodClassIndex >= 0;

  static FastTextBinaryModel parseAndVerify(
    Uint8List bytes, {
    String? expectedSha256,
  }) {
    if (bytes.length < 32) {
      throw const FormatException('Model binary truncated (< 32 bytes).');
    }
    if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
      final actualSha = sha256.convert(bytes).toString().toLowerCase();
      if (actualSha != expectedSha256.trim().toLowerCase()) {
        throw FormatException(
          'Model SHA-256 mismatch (expected $expectedSha256, got $actualSha).',
        );
      }
    }

    // Verify ASCII "LFTQ"
    if (bytes[0] != 0x4C ||
        bytes[1] != 0x46 ||
        bytes[2] != 0x54 ||
        bytes[3] != 0x51) {
      throw const FormatException('Invalid LFTQ model magic bytes.');
    }

    final bd = ByteData.sublistView(bytes);
    final ver = bd.getUint32(4, Endian.little);
    if (ver != 1) {
      throw FormatException('Unsupported LFTQ version: $ver');
    }

    final k = bd.getUint32(8, Endian.little);
    final dim = bd.getUint32(12, Endian.little);
    final buckets = bd.getUint32(16, Endian.little);
    final wordNgrams = bd.getUint16(20, Endian.little);
    final minSub = bd.getUint16(22, Endian.little);
    final maxSub = bd.getUint16(24, Endian.little);
    final temp = bd.getFloat32(28, Endian.little);

    if (k == 0 || k > 512 || dim == 0 || dim > 512 || buckets == 0) {
      throw const FormatException('Invalid LFTQ tensor dimensions.');
    }

    var offset = 32;
    final labels = <String>[];
    for (var i = 0; i < k; i++) {
      if (offset + 2 > bytes.length) {
        throw const FormatException('Corrupt LFTQ label table.');
      }
      final strLen = bd.getUint16(offset, Endian.little);
      offset += 2;
      if (offset + strLen > bytes.length) {
        throw const FormatException('Truncated LFTQ label string.');
      }
      labels.add(
        utf8.decode(Uint8List.sublistView(bytes, offset, offset + strLen)),
      );
      offset += strLen;
    }

    final scalesBytes = buckets * 4;
    final qaBytes = buckets * dim;
    final wBytes = k * dim * 4;
    final bBytes = k * 4;
    if (offset + scalesBytes + qaBytes + wBytes + bBytes > bytes.length) {
      throw const FormatException('Truncated LFTQ tensor payload.');
    }

    final scalesA = Float32List(buckets);
    for (var i = 0; i < buckets; i++) {
      scalesA[i] = bd.getFloat32(offset + i * 4, Endian.little);
    }
    offset += scalesBytes;

    final weightsA = Int8List.fromList(
      Int8List.sublistView(bytes, offset, offset + qaBytes),
    );
    offset += qaBytes;

    final wCount = k * dim;
    final weightsW = Float32List(wCount);
    for (var i = 0; i < wCount; i++) {
      weightsW[i] = bd.getFloat32(offset + i * 4, Endian.little);
    }
    offset += wBytes;

    final biasB = Float32List(k);
    for (var i = 0; i < k; i++) {
      biasB[i] = bd.getFloat32(offset + i * 4, Endian.little);
    }

    final oodIndex = labels.indexOf(oodLabel);
    final inDomainCount = oodIndex >= 0 ? (k - 1) : k;

    return FastTextBinaryModel._(
      version: ver,
      numClasses: inDomainCount,
      totalClasses: k,
      dim: dim,
      numBuckets: buckets,
      wordNgrams: wordNgrams,
      minSubword: minSub,
      maxSubword: maxSub,
      temperature: temp > 1e-4 ? temp : 1.0,
      labels: List.unmodifiable(labels),
      oodClassIndex: oodIndex,
      scalesA: scalesA,
      weightsA: weightsA,
      weightsW: weightsW,
      biasB: biasB,
    );
  }

  /// Exact 32-bit FNV-1a UTF-8 hash (safe across 64-bit VM AND 53-bit Web JS!).
  static int fnv1a32Utf8(String s) {
    final data = utf8.encode(s);
    var h = 0x811C9DC5;
    for (final b in data) {
      h ^= (b & 0xFF);
      // 0x01000193 = (1 << 24) + 0x193 -> intermediate stays < 2^41
      h = (((h << 24) & 0xFFFFFFFF) + ((h * 0x193) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    }
    return h;
  }

  /// Extracts exact same feature bucket indices as `feature_spec.py`.
  List<int> extractFeatureBuckets(String normalizedClassifierInput) {
    final trimmed = normalizedClassifierInput.trim();
    if (trimmed.isEmpty) return const [];
    final accentedTokens = trimmed
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    if (accentedTokens.isEmpty) return const [];

    final asciiTokens = accentedTokens
        .map(FinancialTextNormalizer.stripVnAccents)
        .toList();
    final bucketIds = <int>[];

    for (var i = 0; i < accentedTokens.length; i++) {
      final wHash = fnv1a32Utf8('w:${accentedTokens[i]}') % numBuckets;
      bucketIds.add(wHash);
      bucketIds.add(wHash);
      bucketIds.add(fnv1a32Utf8('a:${asciiTokens[i]}') % numBuckets);
    }

    final nTok = accentedTokens.length;
    for (var n = 2; n <= wordNgrams; n++) {
      for (var i = 0; i <= nTok - n; i++) {
        final bgAcc = accentedTokens.sublist(i, i + n).join('_');
        final bgAsc = asciiTokens.sublist(i, i + n).join('_');
        final ngHash = fnv1a32Utf8('ng:$bgAcc') % numBuckets;
        bucketIds.add(ngHash);
        if (n == 2) {
          bucketIds.add(ngHash);
        }
        bucketIds.add(fnv1a32Utf8('na:$bgAsc') % numBuckets);
      }
    }

    if (maxSubword >= minSubword && minSubword > 0) {
      for (final wAsc in asciiTokens) {
        if (wAsc.length < 4) continue;
        final framed = '<$wAsc>';
        final len = framed.length;
        final upper = maxSubword < len ? maxSubword : len;
        for (var subLen = minSubword; subLen <= upper; subLen++) {
          for (var s = 0; s <= len - subLen; s++) {
            final sub = framed.substring(s, s + subLen);
            bucketIds.add(fnv1a32Utf8('s:$sub') % numBuckets);
          }
        }
      }
    }

    return bucketIds;
  }

  Float32List evaluateProbsFromBuckets(List<int> bucketIds) {
    final k = totalClasses;
    final probs = Float32List(k);
    if (bucketIds.isEmpty) {
      final u = 1.0 / k;
      for (var c = 0; c < k; c++) {
        probs[c] = u;
      }
      return probs;
    }

    final h = Float32List(dim);
    for (final bId in bucketIds) {
      final sc = scalesA[bId];
      if (sc == 0.0) continue;
      final base = bId * dim;
      for (var d = 0; d < dim; d++) {
        h[d] += weightsA[base + d] * sc;
      }
    }
    final invLen = 1.0 / bucketIds.length;
    for (var d = 0; d < dim; d++) {
      h[d] *= invLen;
    }

    final invTemp = 1.0 / temperature;
    var maxLogit = -1e30;
    for (var c = 0; c < k; c++) {
      final wBase = c * dim;
      var sum = biasB[c];
      for (var d = 0; d < dim; d++) {
        sum += weightsW[wBase + d] * h[d];
      }
      final scaled = sum * invTemp;
      probs[c] = scaled;
      if (scaled > maxLogit) {
        maxLogit = scaled;
      }
    }

    var expSum = 0.0;
    for (var c = 0; c < k; c++) {
      final e = math.exp(probs[c] - maxLogit);
      probs[c] = e;
      expSum += e;
    }
    final invSum = expSum > 0.0 ? (1.0 / expSum) : (1.0 / k);
    for (var c = 0; c < k; c++) {
      probs[c] *= invSum;
    }
    return probs;
  }

  /// Unified OOD probability lookup (`0.0` when model has no `__ood__` class).
  double oodProbabilityFrom(Float32List probs) {
    if (oodClassIndex < 0 || oodClassIndex >= probs.length) return 0.0;
    return probs[oodClassIndex];
  }

  /// Best in-domain `(label, probability)` excluding `__ood__`.
  ({String label, double probability}) bestInDomainFrom(Float32List probs) {
    var bestIdx = -1;
    var bestProb = -1.0;
    for (var i = 0; i < labels.length && i < probs.length; i++) {
      if (i == oodClassIndex) continue;
      if (probs[i] > bestProb) {
        bestProb = probs[i];
        bestIdx = i;
      }
    }
    if (bestIdx < 0) {
      return (label: oodLabel, probability: 0.0);
    }
    return (label: labels[bestIdx], probability: bestProb);
  }

  /// Unified runtime OOD check synchronized with `evaluate_all_models.py` and `meta.json`.
  bool isRejectedAsOod(
    Float32List probs, {
    double oodRejectThreshold = 0.40,
    double lowConfidenceThreshold = 0.34,
  }) {
    var topIdx = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[topIdx]) topIdx = i;
    }
    final topLabel = labels[topIdx];
    final oodProb = oodProbabilityFrom(probs);
    final bestInDomain = bestInDomainFrom(probs).probability;
    return topLabel == oodLabel ||
        oodProb >= oodRejectThreshold ||
        bestInDomain < lowConfidenceThreshold;
  }
}
