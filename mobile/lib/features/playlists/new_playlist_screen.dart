import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:google_fonts/google_fonts.dart';

import '../../core/navigation/route_back.dart';
import '../../core/theme/app_colors.dart';

import '../../core/theme/app_icons.dart';

import '../../core/theme/app_radii.dart';

import '../../core/theme/app_theme.dart';

import '../../l10n/app_localizations.dart';

import '../../providers/playback_providers.dart';

import '../../data/repositories/playlist_repository.dart';
import '../../providers/repository_providers.dart';

class NewPlaylistScreen extends ConsumerStatefulWidget {
  const NewPlaylistScreen({super.key});

  @override
  ConsumerState<NewPlaylistScreen> createState() => _NewPlaylistScreenState();
}

class _NewPlaylistScreenState extends ConsumerState<NewPlaylistScreen> {
  final _nameController = TextEditingController();

  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();

    super.dispose();
  }

  List<String> _suggestions(BuildContext context) {
    final l10n = context.l10n;

    return [l10n.ideaMorningWhispers, l10n.ideaWorkFocus, l10n.ideaEveningCalm];
  }

  Future<void> _create() async {
    final l10n = context.l10n;

    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enterPlaylistName)),
      );

      return;
    }

    setState(() => _creating = true);

    try {
      final playlist = await ref.read(playlistRepositoryProvider).create(name);

      ref.invalidate(playlistsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.createdPlaylist(name))),
        );

        context.pushReplacement('/playlists/${playlist.id}');
      }
    } on PlaylistLimitException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.playlistLimitReached(e.limit))),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final theme = whisperTheme(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: theme.isDark
                  ? [AppColors.deep2, AppColors.deep]
                  : [AppColors.lightBg, AppColors.lightBg2],
            ),
          ),
        ),
        _Ambience(isDark: theme.isDark),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                _SubTopBar(
                  theme: theme,
                  title: l10n.newPlaylist,
                  onBack: _creating ? null : () => popOrGo(context, '/playlists'),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      _HeroIcon(theme: theme),
                      const SizedBox(height: 24),
                      Text(
                        l10n.buildCollection,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: theme.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.createAPlaylist,
                        style: GoogleFonts.fraunces(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: theme.foreground,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.createPlaylistDescription,
                        style: TextStyle(
                          color: theme.muted,
                          fontSize: 14,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _NameField(
                        theme: theme,
                        controller: _nameController,
                        enabled: !_creating,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.quickIdeas,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.35,
                          color: theme.muted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _suggestions(context).map((name) {
                          return _SuggestionChip(
                            theme: theme,
                            label: name,
                            onTap: _creating
                                ? null
                                : () => setState(() {
                                      _nameController.text = name;

                                      _nameController.selection =
                                          TextSelection.collapsed(
                                        offset: name.length,
                                      );
                                    }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      _InfoCard(theme: theme),
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        onPressed: _creating ? null : _create,
                        icon: _creating
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.onActionFill,
                                ),
                              )
                            : const Icon(AppIcons.add, size: 18),
                        label: Text(
                            _creating ? l10n.creating : l10n.createPlaylist),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Ambience extends StatelessWidget {
  const _Ambience({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    AppColors.brandLight.withValues(alpha: isDark ? 0.1 : 0.08),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubTopBar extends StatelessWidget {
  const _SubTopBar({required this.theme, required this.title, this.onBack});

  final WhisperThemeExtension theme;

  final String title;

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: Icon(AppIcons.back, color: theme.foreground),
            style: IconButton.styleFrom(
              backgroundColor: theme.isDark ? theme.glass : Colors.white,
              disabledBackgroundColor: theme.isDark
                  ? theme.glass.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
                side: BorderSide(color: theme.glassBorder),
              ),
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.fraunces(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.foreground,
              ),
            ),
          ),
          const SizedBox(width: 42),
        ],
      ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon({required this.theme});

  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandLight
                  .withValues(alpha: theme.isDark ? 0.14 : 0.1),
            ),
          ),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              gradient: AppColors.neonGradient,
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.neon.withValues(alpha: 0.5),
                  blurRadius: 26,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(AppIcons.playlists, size: 32, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({
    required this.theme,
    required this.controller,
    required this.enabled,
  });

  final WhisperThemeExtension theme;

  final TextEditingController controller;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.glass : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: theme.glassBorder),
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: theme.foreground,
        ),
        decoration: InputDecoration(
          labelText: l10n.playlistName,
          hintText: l10n.playlistNameHint,
          labelStyle: TextStyle(color: theme.muted, fontSize: 13),
          hintStyle: TextStyle(color: theme.muted.withValues(alpha: 0.7)),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.theme,
    required this.label,
    this.onTap,
  });

  final WhisperThemeExtension theme;

  final String label;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.isDark ? theme.glass : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(100),
        side: BorderSide(color: theme.glassBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.theme});

  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.glass : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: theme.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.clips, size: 18, color: theme.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n.afterCreatingHint,
              style: TextStyle(fontSize: 13, color: theme.muted, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
