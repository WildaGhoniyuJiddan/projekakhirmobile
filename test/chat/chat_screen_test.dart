import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/screens/chat_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createChatScreen() {
    return const ProviderScope(
      child: MaterialApp(
        home: ChatScreen(),
      ),
    );
  }

  testWidgets('ChatScreen disables delete button when no user messages exist',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(createChatScreen());
    await tester.pumpAndSettle();

    final deleteBtn =
        find.widgetWithIcon(IconButton, Icons.delete_outline);
    expect(deleteBtn, findsOneWidget);

    final btnWidget = tester.widget<IconButton>(deleteBtn);
    expect(btnWidget.onPressed, isNull);
  });

  testWidgets('ChatScreen loads history from SharedPreferences',
      (tester) async {
    final mockHistory = [
      {
        'role': 'user',
        'text': 'rekomendasi pc 10 juta',
        'excludeFromHistory': false,
      },
      {
        'role': 'assistant',
        'text': 'Ini speknya',
        'build': {
          'items': [
            {'component': 'CPU', 'name': 'Ryzen 5 5600', 'price': 1850000},
          ],
          'total': 1850000,
          'note': 'Siap pakai',
        },
        'excludeFromHistory': false,
      },
    ];

    SharedPreferences.setMockInitialValues({
      'dodo_chat_history_v1': jsonEncode(mockHistory),
    });

    await tester.pumpWidget(createChatScreen());
    await tester.pumpAndSettle();

    expect(find.text('rekomendasi pc 10 juta'), findsOneWidget);
    expect(find.text('Ini speknya'), findsOneWidget);
    expect(find.text('CPU: Ryzen 5 5600'), findsOneWidget);

    // Delete button should now be enabled
    final deleteBtn =
        find.widgetWithIcon(IconButton, Icons.delete_outline);
    final btnWidget = tester.widget<IconButton>(deleteBtn);
    expect(btnWidget.onPressed, isNotNull);
  });

  testWidgets(
      'ChatScreen delete button shows confirmation dialog and clears history',
      (tester) async {
    final mockHistory = [
      {
        'role': 'user',
        'text': 'halo dodo',
        'excludeFromHistory': false,
      },
    ];

    SharedPreferences.setMockInitialValues({
      'dodo_chat_history_v1': jsonEncode(mockHistory),
    });

    await tester.pumpWidget(createChatScreen());
    await tester.pumpAndSettle();

    expect(find.text('halo dodo'), findsOneWidget);

    // Tap delete button
    await tester.tap(find.byTooltip(AppStrings.chatNew));
    await tester.pumpAndSettle();

    // Dialog appears
    expect(find.text(AppStrings.chatClearConfirmTitle), findsOneWidget);
    expect(find.text(AppStrings.chatClearConfirmMessage), findsOneWidget);

    // Tap "Hapus & Mulai Baru"
    await tester.tap(find.text(AppStrings.chatClearButton));
    await tester.pumpAndSettle();

    // Previous message gone, welcome message restored
    expect(find.text('halo dodo'), findsNothing);
    expect(find.text(AppStrings.chatWelcome), findsOneWidget);

    // Verify SharedPreferences key was cleared
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('dodo_chat_history_v1'), isFalse);
  });
}
