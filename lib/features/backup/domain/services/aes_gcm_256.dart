import 'dart:typed_data';

/// Pure-Dart NIST FIPS-197 AES-256 + NIST SP 800-38D Galois/Counter Mode (GCM) AEAD.
///
/// Zero external or Flutter dependencies so the domain backup codec remains
/// 100% pure Dart and cross-platform portable.
final class Aes256Gcm {
  Aes256Gcm._();

  static const int keyLengthBytes = 32;
  static const int recommendedNonceLengthBytes = 12;
  static const int tagLengthBytes = 16;

  static const List<int> _sbox = <int>[
    0x63,
    0x7c,
    0x77,
    0x7b,
    0xf2,
    0x6b,
    0x6f,
    0xc5,
    0x30,
    0x01,
    0x67,
    0x2b,
    0xfe,
    0xd7,
    0xab,
    0x76,
    0xca,
    0x82,
    0xc9,
    0x7d,
    0xfa,
    0x59,
    0x47,
    0xf0,
    0xad,
    0xd4,
    0xa2,
    0xaf,
    0x9c,
    0xa4,
    0x72,
    0xc0,
    0xb7,
    0xfd,
    0x93,
    0x26,
    0x36,
    0x3f,
    0xf7,
    0xcc,
    0x34,
    0xa5,
    0xe5,
    0xf1,
    0x71,
    0xd8,
    0x31,
    0x15,
    0x04,
    0xc7,
    0x23,
    0xc3,
    0x18,
    0x96,
    0x05,
    0x9a,
    0x07,
    0x12,
    0x80,
    0xe2,
    0xeb,
    0x27,
    0xb2,
    0x75,
    0x09,
    0x83,
    0x2c,
    0x1a,
    0x1b,
    0x6e,
    0x5a,
    0xa0,
    0x52,
    0x3b,
    0xd6,
    0xb3,
    0x29,
    0xe3,
    0x2f,
    0x84,
    0x53,
    0xd1,
    0x00,
    0xed,
    0x20,
    0xfc,
    0xb1,
    0x5b,
    0x6a,
    0xcb,
    0xbe,
    0x39,
    0x4a,
    0x4c,
    0x58,
    0xcf,
    0xd0,
    0xef,
    0xaa,
    0xfb,
    0x43,
    0x4d,
    0x33,
    0x85,
    0x45,
    0xf9,
    0x02,
    0x7f,
    0x50,
    0x3c,
    0x9f,
    0xa8,
    0x51,
    0xa3,
    0x40,
    0x8f,
    0x92,
    0x9d,
    0x38,
    0xf5,
    0xbc,
    0xb6,
    0xda,
    0x21,
    0x10,
    0xff,
    0xf3,
    0xd2,
    0xcd,
    0x0c,
    0x13,
    0xec,
    0x5f,
    0x97,
    0x44,
    0x17,
    0xc4,
    0xa7,
    0x7e,
    0x3d,
    0x64,
    0x5d,
    0x19,
    0x73,
    0x60,
    0x81,
    0x4f,
    0xdc,
    0x22,
    0x2a,
    0x90,
    0x88,
    0x46,
    0xee,
    0xb8,
    0x14,
    0xde,
    0x5e,
    0x0b,
    0xdb,
    0xe0,
    0x32,
    0x3a,
    0x0a,
    0x49,
    0x06,
    0x24,
    0x5c,
    0xc2,
    0xd3,
    0xac,
    0x62,
    0x91,
    0x95,
    0xe4,
    0x79,
    0xe7,
    0xc8,
    0x37,
    0x6d,
    0x8d,
    0xd5,
    0x4e,
    0xa9,
    0x6c,
    0x56,
    0xf4,
    0xea,
    0x65,
    0x7a,
    0xae,
    0x08,
    0xba,
    0x78,
    0x25,
    0x2e,
    0x1c,
    0xa6,
    0xb4,
    0xc6,
    0xe8,
    0xdd,
    0x74,
    0x1f,
    0x4b,
    0xbd,
    0x8b,
    0x8a,
    0x70,
    0x3e,
    0xb5,
    0x66,
    0x48,
    0x03,
    0xf6,
    0x0e,
    0x61,
    0x35,
    0x57,
    0xb9,
    0x86,
    0xc1,
    0x1d,
    0x9e,
    0xe1,
    0xf8,
    0x98,
    0x11,
    0x69,
    0xd9,
    0x8e,
    0x94,
    0x9b,
    0x1e,
    0x87,
    0xe9,
    0xce,
    0x55,
    0x28,
    0xdf,
    0x8c,
    0xa1,
    0x89,
    0x0d,
    0xbf,
    0xe6,
    0x42,
    0x68,
    0x41,
    0x99,
    0x2d,
    0x0f,
    0xb0,
    0x54,
    0xbb,
    0x16,
  ];

  static const List<int> _rcon = <int>[
    0x00,
    0x01,
    0x02,
    0x04,
    0x08,
    0x10,
    0x20,
    0x40,
    0x80,
    0x1b,
    0x36,
  ];

  static final List<int> _gfRed16 = _buildGfRed16();

  static List<int> _buildGfRed16() {
    final table = List<int>.filled(16, 0);
    for (var n = 0; n < 16; n++) {
      var acc = 0;
      if ((n & 0x08) != 0) acc ^= 0xE100;
      if ((n & 0x04) != 0) acc ^= 0x7080;
      if ((n & 0x02) != 0) acc ^= 0x3840;
      if ((n & 0x01) != 0) acc ^= 0x1C20;
      table[n] = acc;
    }
    return List<int>.unmodifiable(table);
  }

  /// Encrypts [plaintext] using AES-256-GCM with [key] (32 bytes), [nonce] (non-empty),
  /// and optional [aad], returning `(ciphertext, tag)` where `tag` is 16 bytes.
  static ({Uint8List ciphertext, Uint8List tag}) encrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List plaintext,
    Uint8List? aad,
  }) {
    _validateInputs(key: key, nonce: nonce);
    final roundKeys = _expandAes256Key(key);
    final h = Uint8List(16);
    _aesEncryptBlock(roundKeys, Uint8List(16), h);
    final mulTable = _build4BitMulTable(h);

    final j0 = _deriveJ0(mulTable, nonce);
    final icb = Uint8List.fromList(j0);
    _inc32(icb);

    final ciphertext = _gctr(roundKeys, icb, plaintext);
    final s = _ghash(
      mulTable: mulTable,
      aad: aad ?? Uint8List(0),
      ciphertext: ciphertext,
    );

    final tagMask = Uint8List(16);
    _aesEncryptBlock(roundKeys, j0, tagMask);
    final tag = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      tag[i] = s[i] ^ tagMask[i];
    }
    return (ciphertext: ciphertext, tag: tag);
  }

  /// Authenticates and decrypts [ciphertext] using AES-256-GCM.
  /// Throws [FormatException] fail-closed if tag verification fails.
  static Uint8List decrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List ciphertext,
    required Uint8List tag,
    Uint8List? aad,
  }) {
    _validateInputs(key: key, nonce: nonce);
    if (tag.length != tagLengthBytes) {
      throw const FormatException(
        'Độ dài thẻ xác thực AES-256-GCM không hợp lệ.',
      );
    }
    final roundKeys = _expandAes256Key(key);
    final h = Uint8List(16);
    _aesEncryptBlock(roundKeys, Uint8List(16), h);
    final mulTable = _build4BitMulTable(h);

    final j0 = _deriveJ0(mulTable, nonce);
    final s = _ghash(
      mulTable: mulTable,
      aad: aad ?? Uint8List(0),
      ciphertext: ciphertext,
    );

    final tagMask = Uint8List(16);
    _aesEncryptBlock(roundKeys, j0, tagMask);
    var diff = 0;
    for (var i = 0; i < 16; i++) {
      diff |= (s[i] ^ tagMask[i]) ^ tag[i];
    }
    if (diff != 0) {
      throw const FormatException(
        'Xác thực AEAD AES-256-GCM thất bại (sai mật khẩu hoặc tệp bị chỉnh sửa).',
      );
    }

    final icb = Uint8List.fromList(j0);
    _inc32(icb);
    return _gctr(roundKeys, icb, ciphertext);
  }

  static void _validateInputs({
    required Uint8List key,
    required Uint8List nonce,
  }) {
    if (key.length != keyLengthBytes) {
      throw ArgumentError.value(
        key.length,
        'key.length',
        'AES-256-GCM requires a 32-byte key.',
      );
    }
    if (nonce.isEmpty) {
      throw ArgumentError.value(
        nonce.length,
        'nonce.length',
        'AES-256-GCM requires a non-empty nonce.',
      );
    }
  }

  static Uint32List _expandAes256Key(Uint8List key) {
    final w = Uint32List(60);
    for (var i = 0; i < 8; i++) {
      w[i] =
          (key[4 * i] << 24) |
          (key[4 * i + 1] << 16) |
          (key[4 * i + 2] << 8) |
          key[4 * i + 3];
    }
    for (var i = 8; i < 60; i++) {
      var temp = w[i - 1];
      if (i % 8 == 0) {
        temp =
            _subWord(((temp << 8) | (temp >>> 24)) & 0xFFFFFFFF) ^
            (_rcon[i ~/ 8] << 24);
      } else if (i % 8 == 4) {
        temp = _subWord(temp);
      }
      w[i] = (w[i - 8] ^ temp) & 0xFFFFFFFF;
    }
    return w;
  }

  static int _subWord(int word) {
    return (_sbox[(word >>> 24) & 0xFF] << 24) |
        (_sbox[(word >>> 16) & 0xFF] << 16) |
        (_sbox[(word >>> 8) & 0xFF] << 8) |
        _sbox[word & 0xFF];
  }

  static int _xtime(int b) => ((b << 1) ^ ((b & 0x80) != 0 ? 0x1B : 0)) & 0xFF;

  static void _aesEncryptBlock(
    Uint32List roundKeys,
    Uint8List input,
    Uint8List output,
  ) {
    final s = Uint8List.fromList(input);

    void addRoundKey(int round) {
      final base = round * 4;
      for (var c = 0; c < 4; c++) {
        final rk = roundKeys[base + c];
        final col = c * 4;
        s[col] ^= (rk >>> 24) & 0xFF;
        s[col + 1] ^= (rk >>> 16) & 0xFF;
        s[col + 2] ^= (rk >>> 8) & 0xFF;
        s[col + 3] ^= rk & 0xFF;
      }
    }

    void subBytesAndShiftRows() {
      final b0 = _sbox[s[0]];
      final b4 = _sbox[s[4]];
      final b8 = _sbox[s[8]];
      final b12 = _sbox[s[12]];

      final b1 = _sbox[s[5]];
      final b5 = _sbox[s[9]];
      final b9 = _sbox[s[13]];
      final b13 = _sbox[s[1]];

      final b2 = _sbox[s[10]];
      final b6 = _sbox[s[14]];
      final b10 = _sbox[s[2]];
      final b14 = _sbox[s[6]];

      final b3 = _sbox[s[15]];
      final b7 = _sbox[s[3]];
      final b11 = _sbox[s[7]];
      final b15 = _sbox[s[11]];

      s[0] = b0;
      s[1] = b1;
      s[2] = b2;
      s[3] = b3;
      s[4] = b4;
      s[5] = b5;
      s[6] = b6;
      s[7] = b7;
      s[8] = b8;
      s[9] = b9;
      s[10] = b10;
      s[11] = b11;
      s[12] = b12;
      s[13] = b13;
      s[14] = b14;
      s[15] = b15;
    }

    void mixColumns() {
      for (var c = 0; c < 4; c++) {
        final col = c * 4;
        final a0 = s[col];
        final a1 = s[col + 1];
        final a2 = s[col + 2];
        final a3 = s[col + 3];
        final t = a0 ^ a1 ^ a2 ^ a3;
        s[col] = a0 ^ t ^ _xtime(a0 ^ a1);
        s[col + 1] = a1 ^ t ^ _xtime(a1 ^ a2);
        s[col + 2] = a2 ^ t ^ _xtime(a2 ^ a3);
        s[col + 3] = a3 ^ t ^ _xtime(a3 ^ a0);
      }
    }

    addRoundKey(0);
    for (var round = 1; round < 14; round++) {
      subBytesAndShiftRows();
      mixColumns();
      addRoundKey(round);
    }
    subBytesAndShiftRows();
    addRoundKey(14);
    output.setAll(0, s);
  }

  static List<Uint8List> _build4BitMulTable(Uint8List h) {
    final m = List<Uint8List>.generate(16, (_) => Uint8List(16));
    m[8].setAll(0, h);
    for (var i = 4; i >= 1; i >>= 1) {
      final prev = m[i << 1];
      final cur = m[i];
      final lsb = prev[15] & 1;
      for (var k = 15; k > 0; k--) {
        cur[k] = ((prev[k] >> 1) | ((prev[k - 1] & 1) << 7)) & 0xFF;
      }
      cur[0] = (prev[0] >> 1) & 0xFF;
      if (lsb != 0) {
        cur[0] ^= 0xE1;
      }
    }
    for (var i = 2; i < 16; i <<= 1) {
      for (var j = 1; j < i; j++) {
        final dst = m[i + j];
        final a = m[i];
        final b = m[j];
        for (var k = 0; k < 16; k++) {
          dst[k] = a[k] ^ b[k];
        }
      }
    }
    return m;
  }

  static void _gfMulInPlace(Uint8List z, List<Uint8List> mulTable) {
    final x = Uint8List.fromList(z);
    z.fillRange(0, 16, 0);

    for (var byteIdx = 15; byteIdx >= 0; byteIdx--) {
      final b = x[byteIdx];

      // Low nibble
      final lo = b & 0x0F;
      if (byteIdx < 15) {
        _shiftRight4AndXorRem(z);
      }
      final mLo = mulTable[lo];
      for (var k = 0; k < 16; k++) {
        z[k] ^= mLo[k];
      }

      // High nibble
      final hi = (b >> 4) & 0x0F;
      _shiftRight4AndXorRem(z);
      final mHi = mulTable[hi];
      for (var k = 0; k < 16; k++) {
        z[k] ^= mHi[k];
      }
    }
  }

  static void _shiftRight4AndXorRem(Uint8List z) {
    final rem = z[15] & 0x0F;
    for (var k = 15; k > 0; k--) {
      z[k] = ((z[k] >> 4) | ((z[k - 1] & 0x0F) << 4)) & 0xFF;
    }
    z[0] = (z[0] >> 4) & 0xFF;
    final red = _gfRed16[rem];
    z[0] ^= (red >> 8) & 0xFF;
    z[1] ^= red & 0xFF;
  }

  static Uint8List _deriveJ0(List<Uint8List> mulTable, Uint8List nonce) {
    if (nonce.length == 12) {
      final j0 = Uint8List(16);
      j0.setRange(0, 12, nonce);
      j0[15] = 1;
      return j0;
    }
    final j0 = Uint8List(16);
    var offset = 0;
    while (offset < nonce.length) {
      final end = (offset + 16 <= nonce.length) ? offset + 16 : nonce.length;
      for (var i = 0; i < end - offset; i++) {
        j0[i] ^= nonce[offset + i];
      }
      _gfMulInPlace(j0, mulTable);
      offset = end;
    }
    final lenBits = nonce.length * 8;
    _xor64At(j0, 8, lenBits);
    _gfMulInPlace(j0, mulTable);
    return j0;
  }

  static Uint8List _ghash({
    required List<Uint8List> mulTable,
    required Uint8List aad,
    required Uint8List ciphertext,
  }) {
    final y = Uint8List(16);

    void feed(Uint8List data) {
      var offset = 0;
      while (offset < data.length) {
        final end = (offset + 16 <= data.length) ? offset + 16 : data.length;
        for (var i = 0; i < end - offset; i++) {
          y[i] ^= data[offset + i];
        }
        _gfMulInPlace(y, mulTable);
        offset = end;
      }
    }

    feed(aad);
    feed(ciphertext);

    _xor64At(y, 0, aad.length * 8);
    _xor64At(y, 8, ciphertext.length * 8);
    _gfMulInPlace(y, mulTable);
    return y;
  }

  static void _xor64At(Uint8List target, int offset, int bitLen) {
    final hi = (bitLen ~/ 0x100000000) & 0xFFFFFFFF;
    final lo = bitLen & 0xFFFFFFFF;
    target[offset] ^= (hi >>> 24) & 0xFF;
    target[offset + 1] ^= (hi >>> 16) & 0xFF;
    target[offset + 2] ^= (hi >>> 8) & 0xFF;
    target[offset + 3] ^= hi & 0xFF;
    target[offset + 4] ^= (lo >>> 24) & 0xFF;
    target[offset + 5] ^= (lo >>> 16) & 0xFF;
    target[offset + 6] ^= (lo >>> 8) & 0xFF;
    target[offset + 7] ^= lo & 0xFF;
  }

  static void _inc32(Uint8List ctr) {
    var carry = 1;
    for (var i = 15; i >= 12 && carry > 0; i--) {
      final sum = ctr[i] + carry;
      ctr[i] = sum & 0xFF;
      carry = sum >> 8;
    }
  }

  static Uint8List _gctr(Uint32List roundKeys, Uint8List icb, Uint8List input) {
    final out = Uint8List(input.length);
    if (input.isEmpty) return out;
    final cb = Uint8List.fromList(icb);
    final keystream = Uint8List(16);
    var offset = 0;
    while (offset < input.length) {
      _aesEncryptBlock(roundKeys, cb, keystream);
      final chunk = (input.length - offset) < 16 ? (input.length - offset) : 16;
      for (var i = 0; i < chunk; i++) {
        out[offset + i] = input[offset + i] ^ keystream[i];
      }
      offset += chunk;
      _inc32(cb);
    }
    return out;
  }
}
