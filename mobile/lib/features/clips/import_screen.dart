import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

import '../../core/theme/app_icons.dart';

import '../../core/theme/app_radii.dart';

import '../../core/theme/app_theme.dart';

import '../../l10n/app_localizations.dart';

import '../../providers/playback_providers.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  double _progress = 0;

  bool _importing = false;

  String? _fileName;

  Future<void> _pickAndImport() async {
    final l10n = context.l10n;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a'],
    );

    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;

    final title = result.files.single.name;

    setState(() {
      _importing = true;

      _progress = 0;

      _fileName = title;
    });

    try {
      await for (final p
          in ref.read(audioImportServiceProvider).importFile(path, title)) {
        if (mounted) setState(() => _progress = p);
      }

      ref.invalidate(clipsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.importedClip(title))),
        );

        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));

        setState(() => _importing = false);
      }
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
        _ImportAmbience(isDark: theme.isDark),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                _SubTopBar(
                  theme: theme,
                  title: l10n.importTitle,
                  onBack: _importing ? null : () => context.pop(),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      _UploadHero(theme: theme),
                      const SizedBox(height: 24),
                      Text(
                        l10n.addAudio,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: theme.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.importFromDevice,
                        style: GoogleFonts.fraunces(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: theme.foreground,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.importBody,
                        style: TextStyle(
                          color: theme.muted,
                          fontSize: 14,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _FormatChip(label: 'MP3', theme: theme),
                          _FormatChip(label: 'M4A', theme: theme),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (_importing) ...[
                        _ImportProgressCard(
                          theme: theme,
                          fileName: _fileName ?? l10n.audioFile,
                          progress: _progress,
                        ),
                      ] else ...[
                        _DropZone(
                          theme: theme,
                          onTap: _pickAndImport,
                        ),
                        const SizedBox(height: 16),
                        _InfoCard(theme: theme),
                      ],
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

class _ImportAmbience extends StatelessWidget {
  const _ImportAmbience({required this.isDark});

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
                color: AppColors.success.withValues(alpha: isDark ? 0.1 : 0.08),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubTopBar extends StatelessWidget {
  const _SubTopBar({
    required this.theme,
    required this.title,
    this.onBack,
  });

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

class _UploadHero extends StatelessWidget {
  const _UploadHero({required this.theme});

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
              color: AppColors.success
                  .withValues(alpha: theme.isDark ? 0.14 : 0.1),
            ),
          ),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              color: theme.isDark ? theme.glass : Colors.white,
              border: Border.all(color: theme.glassBorder),
              boxShadow: [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.25),
                  blurRadius: 24,
                ),
              ],
            ),
            child:
                const Icon(AppIcons.upload, size: 32, color: AppColors.success),
          ),
        ],
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({required this.label, required this.theme});

  final String label;

  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.glass : Colors.white,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: theme.glassBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: theme.muted,
        ),
      ),
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({required this.theme, required this.onTap});

  final WhisperThemeExtension theme;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Material(
      color: theme.isDark ? theme.glass : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        side: BorderSide(color: theme.glassBorder, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  color: AppColors.success.withValues(alpha: 0.1),
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.2)),
                ),
                child: const Icon(AppIcons.folderOpen,
                    color: AppColors.success, size: 24),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.chooseAudioFile,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: theme.foreground,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.tapToBrowseAudio,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: theme.muted, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportProgressCard extends StatelessWidget {
  const _ImportProgressCard({
    required this.theme,
    required this.fileName,
    required this.progress,
  });

  final WhisperThemeExtension theme;

  final String fileName;

  final double progress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final pct = (progress * 100).clamp(0, 100).toInt();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.glass : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: theme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  color: AppColors.success.withValues(alpha: 0.1),
                ),
                child: const Icon(AppIcons.audioFile,
                    size: 20, color: AppColors.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.importing,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: theme.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: theme.muted),
                    ),
                  ],
                ),
              ),
              Text(
                '$pct%',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              minHeight: 6,
              backgroundColor: theme.glassBorder,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.copyingFile,
            style: TextStyle(fontSize: 12, color: theme.muted),
          ),
        ],
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
          Icon(AppIcons.shield, size: 18, color: theme.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n.importedClipsStayOnDevice,
              style: TextStyle(fontSize: 13, color: theme.muted, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
