import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'auth_shell.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _terms = false;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_terms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.acceptTermsError)),
      );
      return;
    }
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _loading = false);
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    final l10n = context.l10n;
    final highlights = [
      AuthHighlight(icon: AppIcons.mic, label: l10n.syncClips),
      AuthHighlight(icon: AppIcons.schedule, label: l10n.schedulesLabel),
      AuthHighlight(icon: AppIcons.cloud, label: l10n.cloudBackup),
    ];

    return AuthShell(
      compact: true,
      activeTab: AuthTab.signUp,
      onSignInTap: () => context.go('/sign-in'),
      onSignUpTap: () {},
      title: l10n.createAccountTitle,
      subtitle: l10n.createAccountSubtitle,
      highlights: highlights,
      onBack: () => context.go('/sign-in'),
      guestAction: () => context.go('/home'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthTextField(
            label: l10n.fullName,
            hint: l10n.fullNameHint,
            controller: _name,
            keyboardType: TextInputType.name,
            prefixIcon: AppIcons.person,
            compact: true,
          ),
          const SizedBox(height: 10),
          AuthTextField(
            label: l10n.emailAddress,
            hint: l10n.emailHint,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: AppIcons.mail,
            compact: true,
          ),
          const SizedBox(height: 10),
          AuthTextField(
            label: l10n.password,
            hint: l10n.passwordHintSignup,
            controller: _password,
            obscure: _obscure,
            prefixIcon: AppIcons.lock,
            compact: true,
            onChanged: (_) => setState(() {}),
            suffix: IconButton(
              icon: Icon(
                _obscure ? AppIcons.visibility : AppIcons.visibilityOff,
                color: theme.muted,
                size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          PasswordStrengthBar(password: _password.text, compact: true),
          AuthTermsRow(
            checked: _terms,
            onChanged: (v) => setState(() => _terms = v),
            compact: true,
          ),
          AuthPrimaryButton(
            label: l10n.createAccountButton,
            icon: AppIcons.personAdd,
            loading: _loading,
            onPressed: _signUp,
          ),
          const AuthDivider(compact: true),
          SocialAuthRow(onGoogle: _signUp, onApple: _signUp, compact: true),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(l10n.alreadyHaveAccount, style: TextStyle(color: theme.muted, fontSize: 13)),
          GestureDetector(
            onTap: () => context.go('/sign-in'),
            child: Text(
              l10n.signIn,
              style: TextStyle(color: theme.foreground, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
