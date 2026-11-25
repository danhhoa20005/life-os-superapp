import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PickedReceiptImage {
  final String filePath;
  final String fileName;
  final int sizeBytes;

  const PickedReceiptImage({
    required this.filePath,
    required this.fileName,
    required this.sizeBytes,
  });
}

/// Native Android bridge for selecting a receipt photo from Gallery or Camera
/// (`vn.lifeos.app/receipt_picker`) without requiring broad storage permissions.
class NativeReceiptPickerBridge {
  static const MethodChannel _channel = MethodChannel(
    'vn.lifeos.app/receipt_picker',
  );

  const NativeReceiptPickerBridge();

  bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<PickedReceiptImage?> pickFromGallery() async {
    if (!isSupportedPlatform) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'pickFromGallery',
      );
      return _parseResult(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<PickedReceiptImage?> captureFromCamera() async {
    if (!isSupportedPlatform) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'captureFromCamera',
      );
      return _parseResult(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  PickedReceiptImage? _parseResult(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    final path = (raw['filePath'] as String?)?.trim() ?? '';
    if (path.isEmpty) return null;
    return PickedReceiptImage(
      filePath: path,
      fileName: (raw['fileName'] as String?)?.trim() ?? 'receipt.jpg',
      sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}
