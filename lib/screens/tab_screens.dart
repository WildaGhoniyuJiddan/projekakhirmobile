import 'package:flutter/material.dart';

import 'package:worthbang/screens/history_screen.dart';
import 'package:worthbang/screens/profile_screen.dart';
import 'package:worthbang/screens/search_screen.dart';

export 'home_screen.dart' show HomeScreen;

/// Tab Cari: filter & sort hasil (T5).
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) => const SearchFilterScreen();
}

/// Tab Riwayat: daftar + verifikasi hash chain (T6).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) => const HistoryListScreen();
}

/// Tab Profil (T14).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => const ProfileContentScreen();
}
