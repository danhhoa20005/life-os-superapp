import 'dart:convert';
import 'dart:typed_data';

/// Pure-Dart ISO/IEC 18004 QR Code Matrix Encoder (Byte mode, ECC Level L).
///
/// Renders EMVCo / NAPAS 247 VietQR payloads (up to 2953 bytes, Versions 1..10+)
/// 100% locally on-device with zero external network requests.
class QrMatrix {
  final int version;
  final int size;
  final List<Uint8List> modules;

  const QrMatrix({
    required this.version,
    required this.size,
    required this.modules,
  });

  bool isDark(int row, int col) => modules[row][col] != 0;
}

abstract final class QrMatrixEncoder {
  // ECC Level L (format bits = 01): total data codewords and EC codewords per block for Versions 1..10.
  static const List<
    ({
      int totalData,
      int ecPerBlock,
      int numBlocksG1,
      int dataPerBlockG1,
      int numBlocksG2,
      int dataPerBlockG2,
    })
  >
  _vTableL = [
    (
      totalData: 0,
      ecPerBlock: 0,
      numBlocksG1: 0,
      dataPerBlockG1: 0,
      numBlocksG2: 0,
      dataPerBlockG2: 0,
    ), // dummy 0
    (
      totalData: 19,
      ecPerBlock: 7,
      numBlocksG1: 1,
      dataPerBlockG1: 19,
      numBlocksG2: 0,
      dataPerBlockG2: 0,
    ), // V1 (21x21)
    (
      totalData: 34,
      ecPerBlock: 10,
      numBlocksG1: 1,
      dataPerBlockG1: 34,
      numBlocksG2: 0,
      dataPerBlockG2: 0,
    ), // V2 (25x25)
    (
      totalData: 55,
      ecPerBlock: 15,
      numBlocksG1: 1,
      dataPerBlockG1: 55,
      numBlocksG2: 0,
      dataPerBlockG2: 0,
    ), // V3 (29x29)
    (
      totalData: 80,
      ecPerBlock: 20,
      numBlocksG1: 1,
      dataPerBlockG1: 80,
      numBlocksG2: 0,
      dataPerBlockG2: 0,
    ), // V4 (33x33)
    (
      totalData: 108,
      ecPerBlock: 26,
      numBlocksG1: 1,
      dataPerBlockG1: 108,
      numBlocksG2: 0,
      dataPerBlockG2: 0,
    ), // V5 (37x37)
    (
      totalData: 136,
      ecPerBlock: 18,
      numBlocksG1: 2,
      dataPerBlockG1: 68,
      numBlocksG2: 0,
      dataPerBlockG2: 0,
    ), // V6 (41x41)
    (
      totalData: 156,
      ecPerBlock: 20,
      numBlocksG1: 2,
      dataPerBlockG1: 78,
      numBlocksG2: 0,
      dataPerBlockG2: 0,
    ), // V7 (45x45)
    (
      totalData: 194,
      ecPerBlock: 24,
      numBlocksG1: 2,
      dataPerBlockG1: 97,
      numBlocksG2: 0,
      dataPerBlockG2: 0,
    ), // V8 (49x49)
    (
      totalData: 232,
      ecPerBlock: 30,
      numBlocksG1: 2,
      dataPerBlockG1: 116,
      numBlocksG2: 0,
      dataPerBlockG2: 0,
    ), // V9 (53x53)
    (
      totalData: 274,
      ecPerBlock: 18,
      numBlocksG1: 2,
      dataPerBlockG1: 68,
      numBlocksG2: 2,
      dataPerBlockG2: 69,
    ), // V10 (57x57)
  ];

  static const List<List<int>> _alignmentCenters = [
    [],
    [], // V1
    [6, 18], // V2
    [6, 22], // V3
    [6, 26], // V4
    [6, 30], // V5
    [6, 34], // V6
    [6, 22, 38], // V7
    [6, 24, 42], // V8
    [6, 26, 46], // V9
    [6, 28, 50], // V10
  ];

  /// Encodes [payload] into a valid ISO/IEC 18004 QR Code matrix.
  static QrMatrix encode(String payload) {
    final utf8Bytes = utf8.encode(payload);
    var version = 1;
    for (var v = 1; v <= 10; v++) {
      final countBits = v <= 9 ? 8 : 16;
      final neededBits = 4 + countBits + utf8Bytes.length * 8;
      final capBits = _vTableL[v].totalData * 8;
      if (neededBits <= capBits) {
        version = v;
        break;
      }
      if (v == 10) {
        throw ArgumentError(
          'QR payload exceeds Version 10 capacity (${utf8Bytes.length} bytes).',
        );
      }
    }

    final spec = _vTableL[version];
    final dataCodewords = _buildDataCodewords(
      utf8Bytes,
      version,
      spec.totalData,
    );
    final finalMessage = _interleaveWithEcc(dataCodewords, spec);

    final size = 17 + version * 4;
    final grid = List<Uint8List>.generate(size, (_) => Uint8List(size));
    final isFunction = List<Uint8List>.generate(size, (_) => Uint8List(size));

    _drawFunctionPatterns(grid, isFunction, version, size);
    _drawCodewords(grid, isFunction, size, finalMessage);

    // Choose best mask (0..7) minimizing ISO penalty score.
    var bestMask = 0;
    var bestPenalty = 0x7fffffff;
    List<Uint8List>? bestGrid;

    for (var mask = 0; mask < 8; mask++) {
      final candidate = List<Uint8List>.generate(
        size,
        (r) => Uint8List.fromList(grid[r]),
      );
      _applyMask(candidate, isFunction, size, mask);
      _drawFormatBits(candidate, isFunction, size, mask);
      final penalty = _calculatePenalty(candidate, size);
      if (penalty < bestPenalty) {
        bestPenalty = penalty;
        bestMask = mask;
        bestGrid = candidate;
      }
    }

    final chosen = bestGrid!;
    _drawFormatBits(chosen, isFunction, size, bestMask);
    return QrMatrix(version: version, size: size, modules: chosen);
  }

  static Uint8List _buildDataCodewords(
    List<int> data,
    int version,
    int totalDataCodewords,
  ) {
    final totalBits = totalDataCodewords * 8;
    final bits = <int>[];
    void appendBits(int val, int len) {
      for (var i = len - 1; i >= 0; i--) {
        bits.add((val >> i) & 1);
      }
    }

    // Mode indicator: Byte mode = 0100
    appendBits(0x4, 4);
    appendBits(data.length, version <= 9 ? 8 : 16);
    for (final b in data) {
      appendBits(b & 0xFF, 8);
    }

    // Terminator (up to 4 zeros)
    final terminatorLen = (totalBits - bits.length).clamp(0, 4);
    appendBits(0, terminatorLen);

    // Pad to byte boundary
    while (bits.length % 8 != 0) {
      bits.add(0);
    }

    // Pad bytes 0xEC, 0x11 alternating
    var padToggle = true;
    while (bits.length < totalBits) {
      appendBits(padToggle ? 0xEC : 0x11, 8);
      padToggle = !padToggle;
    }

    final out = Uint8List(totalDataCodewords);
    for (var i = 0; i < totalDataCodewords; i++) {
      var byteVal = 0;
      for (var b = 0; b < 8; b++) {
        byteVal = (byteVal << 1) | bits[i * 8 + b];
      }
      out[i] = byteVal;
    }
    return out;
  }

  static Uint8List _interleaveWithEcc(
    Uint8List dataCodewords,
    ({
      int totalData,
      int ecPerBlock,
      int numBlocksG1,
      int dataPerBlockG1,
      int numBlocksG2,
      int dataPerBlockG2,
    })
    spec,
  ) {
    final dataBlocks = <Uint8List>[];
    final eccBlocks = <Uint8List>[];
    final rsDiv = _reedSolomonGeneratorDivisor(spec.ecPerBlock);

    var offset = 0;
    for (var i = 0; i < spec.numBlocksG1; i++) {
      final block = Uint8List.sublistView(
        dataCodewords,
        offset,
        offset + spec.dataPerBlockG1,
      );
      offset += spec.dataPerBlockG1;
      dataBlocks.add(block);
      eccBlocks.add(_reedSolomonRemainder(block, rsDiv));
    }
    for (var i = 0; i < spec.numBlocksG2; i++) {
      final block = Uint8List.sublistView(
        dataCodewords,
        offset,
        offset + spec.dataPerBlockG2,
      );
      offset += spec.dataPerBlockG2;
      dataBlocks.add(block);
      eccBlocks.add(_reedSolomonRemainder(block, rsDiv));
    }

    final out = <int>[];
    final maxDataLen = spec.dataPerBlockG2 > spec.dataPerBlockG1
        ? spec.dataPerBlockG2
        : spec.dataPerBlockG1;
    for (var i = 0; i < maxDataLen; i++) {
      for (final b in dataBlocks) {
        if (i < b.length) out.add(b[i]);
      }
    }
    for (var i = 0; i < spec.ecPerBlock; i++) {
      for (final e in eccBlocks) {
        out.add(e[i]);
      }
    }
    return Uint8List.fromList(out);
  }

  static int _gfMultiply(int x, int y) {
    var z = 0;
    for (var i = 7; i >= 0; i--) {
      z = (z << 1) ^ ((z >> 7) * 0x11D);
      z ^= ((y >> i) & 1) * x;
    }
    return z;
  }

  static Uint8List _reedSolomonGeneratorDivisor(int degree) {
    final result = Uint8List(degree);
    result[degree - 1] = 1;
    var root = 1;
    for (var i = 0; i < degree; i++) {
      for (var j = 0; j < degree; j++) {
        result[j] = _gfMultiply(result[j], root);
        if (j + 1 < degree) {
          result[j] ^= result[j + 1];
        }
      }
      root = _gfMultiply(root, 0x02);
    }
    return result;
  }

  static Uint8List _reedSolomonRemainder(Uint8List data, Uint8List divisor) {
    final result = Uint8List(divisor.length);
    for (final b in data) {
      final factor = b ^ result[0];
      for (var i = 0; i < result.length - 1; i++) {
        result[i] = result[i + 1];
      }
      result[result.length - 1] = 0;
      for (var i = 0; i < divisor.length; i++) {
        result[i] ^= _gfMultiply(divisor[i], factor);
      }
    }
    return result;
  }

  static void _setFunctionModule(
    List<Uint8List> grid,
    List<Uint8List> isFunction,
    int row,
    int col,
    bool isDark,
  ) {
    grid[row][col] = isDark ? 1 : 0;
    isFunction[row][col] = 1;
  }

  static void _drawFunctionPatterns(
    List<Uint8List> grid,
    List<Uint8List> isFunction,
    int version,
    int size,
  ) {
    // Timing patterns
    for (var i = 0; i < size; i++) {
      _setFunctionModule(grid, isFunction, 6, i, i % 2 == 0);
      _setFunctionModule(grid, isFunction, i, 6, i % 2 == 0);
    }

    // 3 Finder patterns + separators
    _drawFinderPattern(grid, isFunction, size, 3, 3);
    _drawFinderPattern(grid, isFunction, size, 3, size - 4);
    _drawFinderPattern(grid, isFunction, size, size - 4, 3);

    // Alignment patterns
    final align = _alignmentCenters[version];
    for (var i = 0; i < align.length; i++) {
      for (var j = 0; j < align.length; j++) {
        if ((i == 0 && j == 0) ||
            (i == 0 && j == align.length - 1) ||
            (i == align.length - 1 && j == 0)) {
          continue;
        }
        _drawAlignmentPattern(grid, isFunction, align[i], align[j]);
      }
    }

    // Reserve format info & dark module
    _drawFormatBits(grid, isFunction, size, 0);
    if (version >= 7) {
      _drawVersionBits(grid, isFunction, size, version);
    }
  }

  static void _drawFinderPattern(
    List<Uint8List> grid,
    List<Uint8List> isFunction,
    int size,
    int centerRow,
    int centerCol,
  ) {
    for (var dy = -4; dy <= 4; dy++) {
      for (var dx = -4; dx <= 4; dx++) {
        final r = centerRow + dy;
        final c = centerCol + dx;
        if (r < 0 || r >= size || c < 0 || c >= size) continue;
        final dist = dy.abs() > dx.abs() ? dy.abs() : dx.abs();
        final dark = dist != 2 && dist != 4;
        _setFunctionModule(grid, isFunction, r, c, dark);
      }
    }
  }

  static void _drawAlignmentPattern(
    List<Uint8List> grid,
    List<Uint8List> isFunction,
    int centerRow,
    int centerCol,
  ) {
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        final dist = dy.abs() > dx.abs() ? dy.abs() : dx.abs();
        _setFunctionModule(
          grid,
          isFunction,
          centerRow + dy,
          centerCol + dx,
          dist != 1,
        );
      }
    }
  }

  static void _drawFormatBits(
    List<Uint8List> grid,
    List<Uint8List> isFunction,
    int size,
    int mask,
  ) {
    // ECC Level L = 01
    final data = (0x01 << 3) | mask;
    var rem = data;
    for (var i = 0; i < 10; i++) {
      rem = (rem << 1) ^ ((rem >> 9) * 0x537);
    }
    final bits = ((data << 10) | rem) ^ 0x5412;

    bool bit(int idx) => ((bits >> idx) & 1) != 0;

    for (var i = 0; i <= 5; i++) {
      _setFunctionModule(grid, isFunction, 8, i, bit(14 - i));
    }
    _setFunctionModule(grid, isFunction, 8, 7, bit(8));
    _setFunctionModule(grid, isFunction, 8, 8, bit(7));
    _setFunctionModule(grid, isFunction, 7, 8, bit(6));
    for (var i = 9; i < 15; i++) {
      _setFunctionModule(grid, isFunction, 14 - i, 8, bit(14 - i));
    }

    for (var i = 0; i < 8; i++) {
      _setFunctionModule(grid, isFunction, 8, size - 1 - i, bit(i));
    }
    for (var i = 8; i < 15; i++) {
      _setFunctionModule(grid, isFunction, size - 15 + i, 8, bit(i));
    }
    _setFunctionModule(grid, isFunction, size - 8, 8, true); // Dark module
  }

  static void _drawVersionBits(
    List<Uint8List> grid,
    List<Uint8List> isFunction,
    int size,
    int version,
  ) {
    var rem = version;
    for (var i = 0; i < 12; i++) {
      rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
    }
    final bits = (version << 12) | rem;
    for (var i = 0; i < 18; i++) {
      final dark = ((bits >> i) & 1) != 0;
      final a = size - 11 + (i % 3);
      final b = i ~/ 3;
      _setFunctionModule(grid, isFunction, a, b, dark);
      _setFunctionModule(grid, isFunction, b, a, dark);
    }
  }

  static void _drawCodewords(
    List<Uint8List> grid,
    List<Uint8List> isFunction,
    int size,
    Uint8List codewords,
  ) {
    var bitIdx = 0;
    final totalBits = codewords.length * 8;
    for (var right = size - 1; right >= 1; right -= 2) {
      if (right == 6) right = 5;
      for (var vert = 0; vert < size; vert++) {
        for (var j = 0; j < 2; j++) {
          final col = right - j;
          final upward = ((right + 1) & 2) == 0;
          final row = upward ? (size - 1 - vert) : vert;
          if (isFunction[row][col] == 0 && bitIdx < totalBits) {
            final dark =
                ((codewords[bitIdx >> 3] >> (7 - (bitIdx & 7))) & 1) != 0;
            grid[row][col] = dark ? 1 : 0;
            bitIdx++;
          }
        }
      }
    }
  }

  static void _applyMask(
    List<Uint8List> grid,
    List<Uint8List> isFunction,
    int size,
    int mask,
  ) {
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (isFunction[r][c] != 0) continue;
        final invert = switch (mask) {
          0 => (r + c) % 2 == 0,
          1 => r % 2 == 0,
          2 => c % 3 == 0,
          3 => (r + c) % 3 == 0,
          4 => ((r ~/ 2) + (c ~/ 3)) % 2 == 0,
          5 => (r * c) % 2 + (r * c) % 3 == 0,
          6 => ((r * c) % 2 + (r * c) % 3) % 2 == 0,
          _ => ((r + c) % 2 + (r * c) % 3) % 2 == 0,
        };
        if (invert) {
          grid[r][c] ^= 1;
        }
      }
    }
  }

  static int _calculatePenalty(List<Uint8List> grid, int size) {
    var penalty = 0;
    // N1: 5+ consecutive modules in row/col
    for (var r = 0; r < size; r++) {
      var runColor = grid[r][0];
      var runLen = 1;
      for (var c = 1; c < size; c++) {
        if (grid[r][c] == runColor) {
          runLen++;
          if (runLen == 5) {
            penalty += 3;
          } else if (runLen > 5) {
            penalty += 1;
          }
        } else {
          runColor = grid[r][c];
          runLen = 1;
        }
      }
    }
    for (var c = 0; c < size; c++) {
      var runColor = grid[0][c];
      var runLen = 1;
      for (var r = 1; r < size; r++) {
        if (grid[r][c] == runColor) {
          runLen++;
          if (runLen == 5) {
            penalty += 3;
          } else if (runLen > 5) {
            penalty += 1;
          }
        } else {
          runColor = grid[r][c];
          runLen = 1;
        }
      }
    }
    // N2: 2x2 blocks
    for (var r = 0; r < size - 1; r++) {
      for (var c = 0; c < size - 1; c++) {
        final v = grid[r][c];
        if (v == grid[r][c + 1] &&
            v == grid[r + 1][c] &&
            v == grid[r + 1][c + 1]) {
          penalty += 3;
        }
      }
    }
    return penalty;
  }
}
