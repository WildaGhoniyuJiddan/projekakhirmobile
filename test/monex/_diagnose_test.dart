import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/screens/builder_screen.dart';
import 'package:worthbang/screens/price_check_screen.dart';
import 'package:worthbang/services/data/app_database.dart';
import 'package:worthbang/utils/theme.dart';

/// Diagnostik: cari RenderFlex yang overflow, print child-nya.
void main() {
  Future<void> diagnose(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final errors = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    FlutterError.onError = errors.add;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(
            AppDatabase(NativeDatabase.memory()),
          ),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: screen),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    FlutterError.onError = prev;

    for (final e in errors) {
      // ignore: avoid_print
      print('=== OVERFLOW ${screen.runtimeType} ===');
      final node = e.informationCollector?.call().toList() ?? [];
      for (final n in node) {
        final s = '$n';
        if (s.contains('debugCreator')) {
          // ignore: avoid_print
          print('  creator: $s');
        }
      }
    }

    // Cari RenderFlex yang overflow secara manual.
    void walk(RenderObject ro, int depth) {
      if (ro is RenderFlex) {
        // ignore: avoid_print
        final overflow = ro.toString();
        if (overflow.contains('OVERFLOWING')) {
          // ignore: avoid_print
          print('>>> RenderFlex OVERFLOW @depth=$depth size=${ro.size}');
        }
      }
      ro.visitChildren((c) => walk(c, depth + 1));
    }

    walk(tester.binding.rootElement!.renderObject!, 0);
  }

  testWidgets('diagnose price check', (tester) async {
    await diagnose(tester, const PriceCheckScreen());
  });

  testWidgets('diagnose builder', (tester) async {
    await diagnose(tester, const BuilderScreen());
  });
}
