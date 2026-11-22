import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Clean Architecture & BLoC-Only Automated Source Code Guard', () {
    final libDir = Directory('lib');
    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('lib/ contains valid feature-first Dart source files', () {
      expect(dartFiles.length, greaterThanOrEqualTo(30));
    });

    test('ZERO Cubit classes or Cubit usages exist anywhere in lib/', () {
      final violations = <String>[];
      final cubitPattern = RegExp(r'\b(extends\s+Cubit|Cubit<|CubitProvider)\b');

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('//') || line.startsWith('///')) continue;
          if (cubitPattern.hasMatch(line)) {
            violations.add('${file.path}:${i + 1} -> $line');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Cubit is strictly forbidden! Violations:\n${violations.join('\n')}',
      );
    });

    test('Domain layer is 100% pure Dart (zero Flutter, Firebase, or BLoC imports)', () {
      final violations = <String>[];
      final forbiddenImport = RegExp(
        r'''import\s+['"]package:(flutter|flutter_bloc|bloc|cloud_firestore|firebase_auth|firebase_core|google_sign_in|go_router)/''',
      );

      for (final file in dartFiles) {
        final normalizedPath = file.path.replaceAll('\\', '/');
        if (!normalizedPath.contains('/domain/')) continue;

        final content = file.readAsStringSync();
        if (forbiddenImport.hasMatch(content)) {
          violations.add(normalizedPath);
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Domain layer must not depend on Flutter/Firebase/BLoC:\n${violations.join('\n')}',
      );
    });

    test('Presentation layer (BLoCs & Pages) never imports Cloud Firestore or FirebaseAuth SDKs', () {
      final violations = <String>[];
      final forbiddenFirebaseImport = RegExp(
        r'''import\s+['"]package:(cloud_firestore|firebase_auth|google_sign_in)/''',
      );

      for (final file in dartFiles) {
        final normalizedPath = file.path.replaceAll('\\', '/');
        if (!normalizedPath.contains('/presentation/')) continue;

        final content = file.readAsStringSync();
        if (forbiddenFirebaseImport.hasMatch(content)) {
          violations.add(normalizedPath);
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Presentation must never access Firebase SDK directly:\n${violations.join('\n')}',
      );
    });

    test('Feature BLoCs never import another feature BLoC directly', () {
      final violations = <String>[];
      final featuresPrefix = 'lib/features/';

      for (final file in dartFiles) {
        final normalizedPath = file.path.replaceAll('\\', '/');
        if (!normalizedPath.startsWith(featuresPrefix) ||
            !normalizedPath.contains('/presentation/bloc/')) {
          continue;
        }
        final parts = normalizedPath.substring(featuresPrefix.length).split('/');
        final ownFeature = parts.first;

        for (final line in file.readAsLinesSync()) {
          final trimmed = line.trim();
          if (!trimmed.startsWith('import ')) continue;
          if (trimmed.contains('/presentation/bloc/') && !trimmed.contains('/$ownFeature/')) {
            // Check relative parent imports crossing feature boundaries into another bloc
            if (trimmed.contains('../../../') && trimmed.contains('_bloc.dart')) {
              violations.add('$normalizedPath -> $trimmed');
            }
          }
        }
      }

      expect(violations, isEmpty, reason: 'Cross-feature BLoC coupling detected: $violations');
    });
  });
}
