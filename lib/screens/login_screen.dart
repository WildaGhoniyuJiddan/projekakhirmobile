import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:worthbang/providers/providers.dart';
import 'package:worthbang/providers/auth_controller.dart';
import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/services/auth_repository.dart';
import 'package:worthbang/widgets/app_logo.dart';

/// Layar masuk: email + password, opsi biometric, link ke registrasi.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final bio = ref.read(biometricServiceProvider);
    // Tampilkan tombol biometric bila ada sesi tersimpan + user mengaktifkannya.
    final storage = ref.read(tokenStorageProvider);
    final hasSession = (await storage.readRefreshToken())?.isNotEmpty == true;
    final enabled = await storage.isBiometricEnabled();
    final available = await bio.isAvailable;
    if (!mounted) return;
    setState(() => _bioAvailable = hasSession && enabled && available);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final ok = await ref
        .read(authControllerProvider.notifier)
        .login(_email.text.trim(), _password.text);
    if (ok && mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.loginTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            MonexSpacing.screenPaddingH,
            MonexSpacing.screenPaddingV,
            MonexSpacing.screenPaddingH,
            24,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: AppLogo(size: 88, borderRadius: 22)),
                const SizedBox(height: MonexSpacing.sectionGap),
                Text(AppStrings.appTagline,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: MonexSpacing.sectionGap),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: AppStrings.emailLabel,
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? AppStrings.emailInvalid
                      : null,
                ),
                const SizedBox(height: MonexSpacing.gridGap),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: AppStrings.passwordLabel,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 8)
                      ? AppStrings.passwordMin
                      : null,
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 12),
                  Text(state.error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: MonexSpacing.sectionGap),
                MonexPrimaryButton(
                  label: AppStrings.loginButton,
                  loading: state.isLoading,
                  onPressed: state.isLoading ? null : _submit,
                ),
                if (_bioAvailable) ...[
                  const SizedBox(height: 12),
                  MonexSecondaryButton(
                    label: AppStrings.biometricButton,
                    icon: Icons.fingerprint,
                    onPressed: () async {
                      final ok = await ref
                          .read(authControllerProvider.notifier)
                          .unlockWithBiometric();
                      if (ok && context.mounted) context.go('/home');
                    },
                  ),
                ],
                const SizedBox(height: MonexSpacing.gridGap),
                TextButton(
                  onPressed: () => context.push('/register'),
                  child: const Text(AppStrings.goToRegister),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
