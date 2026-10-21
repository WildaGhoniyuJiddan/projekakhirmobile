import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/services/auth/auth_repository.dart';
import 'package:worthbang/providers/auth_controller.dart';
import 'package:worthbang/services/data/sync_queue.dart';
import 'package:worthbang/services/data/sync_service.dart';
import 'package:worthbang/screens/onboarding_screen.dart';
import 'package:worthbang/services/features/profile_api.dart';

/// Tab Profil: foto, nama, pengaturan (biometric/tilt/tema), feedback, logout.
class ProfileContentScreen extends ConsumerStatefulWidget {
  const ProfileContentScreen({super.key});

  @override
  ConsumerState<ProfileContentScreen> createState() =>
      _ProfileContentScreenState();
}

class _ProfileContentScreenState
    extends ConsumerState<ProfileContentScreen> {
  final _picker = ImagePicker();
  final _kesan = TextEditingController();
  final _saran = TextEditingController();
  int _rating = 5;
  bool _sendingFeedback = false;
  bool _bioAvailable = false;
  bool _bioEnabled = false;
  String? _localPhotoPath;

  @override
  void initState() {
    super.initState();
    _loadBio();
    _restorePhoto();
  }

  Future<void> _restorePhoto() async {
    final path = await ProfileApi.localPhotoPath();
    if (mounted && path != null) {
      setState(() => _localPhotoPath = path);
    }
  }

  @override
  void dispose() {
    _kesan.dispose();
    _saran.dispose();
    super.dispose();
  }

  Future<void> _loadBio() async {
    final repo = ref.read(tokenStorageProvider);
    final available =
        await ref.read(biometricServiceProvider).isAvailable;
    final enabled = await repo.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _bioAvailable = available;
        _bioEnabled = enabled;
      });
    }
  }

  Future<void> _pickPhoto() async {
    final xfile =
        await _picker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;
    try {
      final user = await ref
          .read(profileApiProvider)
          .updateProfile(photoPath: xfile.path);
      ref.read(authControllerProvider.notifier).setUser(user);
      if (mounted) {
        setState(() => _localPhotoPath = xfile.path);
        showMonexToast(context, AppStrings.photoUpdated, isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        showMonexToast(context, e.toString(), isError: true);
      }
    }
  }

  Future<void> _editName(String current) async {
    final ctrl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.editNameTitle),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              labelText: AppStrings.nameLabel),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AppStrings.cancelButton),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text(AppStrings.saveButton),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final user =
          await ref.read(profileApiProvider).updateProfile(name: name);
      ref.read(authControllerProvider.notifier).setUser(user);
    } catch (e) {
      if (mounted) {
        showMonexToast(context, e.toString(), isError: true);
      }
    }
  }

  Future<void> _sendFeedback() async {
    setState(() => _sendingFeedback = true);
    try {
      final kesan = _kesan.text.trim();
      final saran = _saran.text.trim();
      final rating = _rating;
      await ref.read(profileApiProvider).sendFeedback(
            rating: rating,
            kesan: kesan,
            saran: saran,
          );
      if (!mounted) return;
      _kesan.clear();
      _saran.clear();
      showMonexToast(context, AppStrings.feedbackSent, isSuccess: true);
    } catch (e) {
      if (mounted) {
        showMonexToast(context, e.toString(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _sendingFeedback = false);
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.logoutTitle),
        content: const Text(AppStrings.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.logoutButton),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    final settings = ref.watch(settingsControllerProvider).orDefault;

    ImageProvider? avatar;
    if (_localPhotoPath != null) {
      avatar = FileImage(File(_localPhotoPath!));
    } else if (user?.photoUrl != null) {
      avatar = NetworkImage(user!.photoUrl!);
    }

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.profileScreenTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            MonexSpacing.screenPaddingH,
            MonexSpacing.screenPaddingV,
            MonexSpacing.screenPaddingH,
            24,
          ),
          children: [
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickPhoto,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 44,
                          backgroundImage: avatar,
                          child: avatar == null
                              ? Text(
                                  (user?.name.isNotEmpty == true
                                          ? user!.name[0]
                                          : '?')
                                      .toUpperCase(),
                                  style: const TextStyle(fontSize: 32),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: MonexColors.lime,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(6),
                            child: const Icon(
                              Icons.camera_alt,
                              size: 16,
                              color: MonexColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(user?.name ?? '-',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () =>
                            _editName(user?.name ?? ''),
                      ),
                    ],
                  ),
                  Text(user?.email ?? '',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(AppStrings.settingsSection,
                style: Theme.of(context).textTheme.titleMedium),
            if (_bioAvailable)
              SwitchListTile(
                title:
                    const Text(AppStrings.biometricSetting),
                subtitle:
                    const Text(AppStrings.biometricSubtitle),
                value: _bioEnabled,
                onChanged: (v) async {
                  await ref
                      .read(tokenStorageProvider)
                      .setBiometricEnabled(v);
                  setState(() => _bioEnabled = v);
                },
              ),
            SwitchListTile(
              title: const Text(AppStrings.tiltSetting),
              subtitle:
                  const Text(AppStrings.tiltSubtitle),
              value: settings.tiltEnabled,
              onChanged: (v) => ref
                  .read(settingsControllerProvider.notifier)
                  .setTiltEnabled(v),
            ),
            ListTile(
              title: const Text(AppStrings.themeSetting),
              // Lebar tetap: ListTile memberi trailing constraint tak
              // terbatas, sedangkan segmented control memakai Expanded.
              trailing: SizedBox(
                width: 156,
                child: MonexSegmentedControl<ThemeMode>(
                  value: settings.themeMode,
                  onChanged: (v) => ref
                      .read(settingsControllerProvider.notifier)
                      .setThemeMode(v),
                  items: const [
                    MonexSegment(
                      value: ThemeMode.system,
                      label: '',
                      icon: Icons.settings_suggest_outlined,
                    ),
                    MonexSegment(
                      value: ThemeMode.light,
                      label: '',
                      icon: Icons.light_mode_outlined,
                    ),
                    MonexSegment(
                      value: ThemeMode.dark,
                      label: '',
                      icon: Icons.dark_mode_outlined,
                    ),
                  ],
                ),
              ),
            ),
            ListTile(
              title: const Text(AppStrings.prefTitle),
              subtitle: const Text(AppStrings.prefProfileSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const OnboardingScreen(),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(AppStrings.feedbackSection,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: List.generate(
                5,
                (i) => IconButton(
                  icon: Icon(
                    i < _rating ? Icons.star : Icons.star_border,
                    color: MonexColors.verdictFair,
                  ),
                  onPressed: () =>
                      setState(() => _rating = i + 1),
                ),
              ),
            ),
            TextField(
              controller: _kesan,
              decoration: const InputDecoration(
                labelText: AppStrings.kesanLabel,
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _saran,
              decoration: const InputDecoration(
                labelText: AppStrings.saranLabel,
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            MonexPrimaryButton(
              onPressed:
                  _sendingFeedback ? null : _sendFeedback,
              icon: Icons.send_outlined,
              label: AppStrings.sendFeedbackButton,
              loading: _sendingFeedback,
            ),
            const SizedBox(height: 8),
            Consumer(
              builder: (context, ref, _) {
                final pending =
                    ref.watch(pendingCountProvider).value ?? 0;
                if (pending == 0) return const SizedBox.shrink();
                return ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: Text(
                      '${AppStrings.pendingSync}: $pending'),
                  trailing: TextButton(
                    onPressed: () async {
                      final rest = await ref
                          .read(syncServiceProvider)
                          .syncPending();
                      ref.invalidate(pendingCountProvider);
                      ref.invalidate(lastSyncAtProvider);
                      if (context.mounted) {
                        showMonexToast(
                          context,
                          '${AppStrings.syncDone}: $rest',
                          isSuccess: true,
                        );
                      }
                    },
                    child:
                        const Text(AppStrings.syncNowButton),
                  ),
                  contentPadding: EdgeInsets.zero,
                );
              },
            ),
            const SizedBox(height: 24),
            MonexSecondaryButton(
              onPressed: _logout,
              icon: Icons.logout_rounded,
              label: AppStrings.logoutButton,
            ),
          ],
        ),
      ),
    );
  }
}
