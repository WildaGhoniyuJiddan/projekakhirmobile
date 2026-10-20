import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/screens/builder_screen.dart';
import 'package:worthbang/widgets/pc_3d_stage.dart';
import 'package:worthbang/services/wglb.dart';

Future<void> _pumpStage(
  WidgetTester tester, {
  required List<WglbVariant> parts,
  bool loading = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: MonexTheme.darkTheme,
        home: Scaffold(
          body: Pc3DStage(
            parts: parts,
            loading: loading,
            label: 'Test Build',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('panggung 3D menampilkan fallback saat part kosong',
      (tester) async {
    await _pumpStage(tester, parts: const []);
    expect(find.text('Menyiapkan model 3D'), findsOneWidget);
    // Tidak ada viewer native yang harus terpasang saat tidak ada data.
    expect(find.byType(Pc3DStage), findsOneWidget);
  });

  testWidgets('panggung 3D menampilkan caption build', (tester) async {
    await _pumpStage(tester, parts: const []);
    expect(find.text('Test Build'), findsOneWidget);
  });

  testWidgets('panggung 3D loader tampil saat loading', (tester) async {
    await _pumpStage(tester, parts: const [], loading: true);
    expect(find.text('Menyusun rakitan…'), findsOneWidget);
  });

  testWidgets('halaman builder tetap bisa dibuka dan panggung terpasang',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: MonexTheme.darkTheme,
          home: const BuilderScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(Pc3DStage), findsOneWidget);
    // Budget field tetap ada: 3D adalah tambahan, bukan pengganti.
    expect(find.byType(TextField), findsOneWidget);
  });
}
