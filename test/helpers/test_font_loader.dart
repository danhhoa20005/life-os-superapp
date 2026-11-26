import 'dart:io';

import 'package:flutter/services.dart';

bool _fontsLoaded = false;

/// Loads the Flutter SDK's bundled Vietnamese-capable `Roboto` font weights
/// and `MaterialIcons` into the test engine so golden and widget screenshots
/// render readable Vietnamese glyphs and Material icons instead of `Ahem` tofu boxes.
Future<void> loadVietnameseTestFonts() async {
  if (_fontsLoaded) return;

  final fontsDir = _resolveFlutterMaterialFontsDir();
  if (fontsDir == null || !fontsDir.existsSync()) {
    return;
  }

  final robotoFiles = <String>[
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
    'roboto-light.ttf',
    'roboto-italic.ttf',
  ];

  // Register under 'Roboto' (Material default) and '.SF Pro Text' / 'sans-serif' aliases.
  for (final family in const <String>['Roboto', 'sans-serif']) {
    final loader = FontLoader(family);
    var added = false;
    for (final name in robotoFiles) {
      final file = File('${fontsDir.path}${Platform.pathSeparator}$name');
      if (file.existsSync()) {
        final bytes = file.readAsBytesSync();
        loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
        added = true;
      }
    }
    if (added) {
      await loader.load();
    }
  }

  final iconFile = File(
    '${fontsDir.path}${Platform.pathSeparator}materialicons-regular.otf',
  );
  if (iconFile.existsSync()) {
    final iconBytes = iconFile.readAsBytesSync();
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(iconBytes)));
    await iconLoader.load();
  }

  _fontsLoaded = true;
}

Directory? _resolveFlutterMaterialFontsDir() {
  final envRoot = Platform.environment['FLUTTER_ROOT'];
  if (envRoot != null && envRoot.trim().isNotEmpty) {
    final candidate = Directory(
      '$envRoot${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}material_fonts',
    );
    if (candidate.existsSync()) return candidate;
  }

  // Walk up from Platform.resolvedExecutable (<flutter>/bin/cache/...)
  var current = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 10; depth++) {
    final directCache = Directory(
      '${current.path}${Platform.pathSeparator}artifacts${Platform.pathSeparator}material_fonts',
    );
    if (directCache.existsSync()) return directCache;

    final fromRoot = Directory(
      '${current.path}${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}material_fonts',
    );
    if (fromRoot.existsSync()) return fromRoot;

    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  return null;
}
