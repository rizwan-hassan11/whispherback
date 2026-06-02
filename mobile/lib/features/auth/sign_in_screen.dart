import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'auth_shell.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _loading = false);
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    final l10n = context.l10n;
    final highlights = [
      AuthHighlight(icon: AppIcons.shield, label: l10n.secure),
      AuthHighlight(icon: AppIcons.cloud, label: l10n.cloudSync),
      AuthHighlight(icon: AppIcons.lock, label: l10n.private),
    ];

    return AuthShell(
      activeTab: AuthTab.signIn,
      compact: true,
      onSignInTap: () {},
      onSignUpTap: () => context.go('/sign-up'),
      title: l10n.welcomeBack,
      subtitle: l10n.signInPageSubtitle,
      highlights: highlights,
      onBack: () => context.canPop() ? context.pop() : context.go('/settings'),
      guestAction: () => context.go('/home'),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(l10n.dontHaveAccount, style: TextStyle(color: theme.muted)),
          GestureDetector(
            onTap: () => context.go('/sign-up'),
            child: Text(
              l10n.signUpFree,
              style: TextStyle(
                  color: theme.foreground, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthTextField(
            label: l10n.emailAddress,
            hint: l10n.emailHint,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: AppIcons.mail,
          ),
          const SizedBox(height: 10),
          AuthTextField(
            label: l10n.password,
            hint: l10n.passwordHint,
            controller: _password,
            obscure: _obscure,
            prefixIcon: AppIcons.lock,
            suffix: IconButton(
              icon: Icon(
                _obscure ? AppIcons.visibility : AppIcons.visibilityOff,
                color: theme.muted,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {},
              child: Text(
                l10n.forgotPassword,
                style: TextStyle(
                  color: theme.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          AuthPrimaryButton(
            label: l10n.signInButton,
            loading: _loading,
            onPressed: _signIn,
          ),
          const AuthDivider(),
          SocialAuthRow(onGoogle: _signIn, onApple: _signIn),
        ],
      ),
    );
  }
}
