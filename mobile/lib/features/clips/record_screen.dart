import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/playback_providers.dart';

class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  final _titleController = TextEditingController();
  bool _recording = false;
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTimer;
  bool _titleInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_titleInitialized) {
      _titleController.text = context.l10n.newRecording;
      _titleInitialized = true;
    }
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _titleController.dispose();
    super.dispose();
  }

  Future<bool> _ensureMicPermission() async {
    final l10n = context.l10n;
    final status = await Permission.microphone.request();
    if (status.isGranted) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.micPermissionSnack)),
      );
    }
    return false;
  }

  Future<void> _toggleRecord() async {
    final l10n = context.l10n;
    final service = ref.read(audioRecordingServiceProvider);
    if (_recording) {
      _elapsedTimer?.cancel();
      final clip = await service.stopAndSave();
      ref.invalidate(clipsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              clip != null ? l10n.savedClip(clip.title) : l10n.recordingCancelled,
            ),
          ),
        );
        context.pop();
      }
    } else {
      if (!await _ensureMicPermission()) return;
      await service.startRecording(_titleController.text.trim());
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
      });
      setState(() {
        _recording = true;
        _elapsed = Duration.zero;
      });
    }
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final recordingService = ref.read(audioRecordingServiceProvider);
    final theme = whisperTheme(context);
    final defaultTitle = l10n.newRecording;

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
        _RecordAmbience(isDark: theme.isDark, recording: _recording),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                _SubTopBar(
                  theme: theme,
                  title: l10n.recordTitle,
                  onBack: _recording ? null : () => context.pop(),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      if (_recording) ...[
                        _RecordingBadge(theme: theme),
                        const SizedBox(height: 28),
                        Text(
                          _formatElapsed(_elapsed),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.fraunces(
                            fontSize: 48,
                            fontWeight: FontWeight.w700,
                            color: theme.foreground,
                            letterSpacing: 2,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 24),
                        StreamBuilder(
                          stream: recordingService.amplitudeStream,
                          builder: (context, snap) {
                            final amp = snap.data?.current ?? -40;
                            final level = ((amp + 40) / 40).clamp(0.0, 1.0);
                            return _WaveformBars(theme: theme, level: level);
                          },
                        ),
                        const SizedBox(height: 28),
                        Text(
                          _titleController.text.trim().isEmpty
                              ? defaultTitle
                              : _titleController.text.trim(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme.muted,
                          ),
                        ),
                      ] else ...[
                        _MicHero(theme: theme),
                        const SizedBox(height: 24),
                        Text(
                          l10n.captureAWhisper,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                            color: theme.muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.recordNewClip,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.fraunces(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: theme.foreground,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l10n.recordSpeakClearlyHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.muted,
                            fontSize: 14,
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _TitleField(theme: theme, controller: _titleController),
                      ],
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _recording ? AppColors.error : AppColors.brand,
                          foregroundColor: _recording ? Colors.white : AppColors.ink,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                        ),
                        onPressed: _toggleRecord,
                        icon: Icon(_recording ? AppIcons.stop : AppIcons.mic),
                        label: Text(_recording ? l10n.stopAndSave : l10n.startRecording),
                      ),
                      if (!_recording) ...[
                        const SizedBox(height: 12),
                        Text(
                          l10n.micPermissionRequired,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: theme.muted),
                        ),
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

class _RecordAmbience extends StatelessWidget {
  const _RecordAmbience({required this.isDark, required this.recording});

  final bool isDark;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final color = recording ? AppColors.error : AppColors.brandLight;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -40,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: recording ? 220 : 180,
                height: recording ? 220 : 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: isDark ? 0.12 : 0.1),
                ),
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
              disabledBackgroundColor: theme.isDark ? theme.glass.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.5),
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

class _RecordingBadge extends StatelessWidget {
  const _RecordingBadge({required this.theme});

  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.error,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              context.l10n.recording,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.error.withValues(alpha: 0.95),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveformBars extends StatelessWidget {
  const _WaveformBars({required this.theme, required this.level});

  final WhisperThemeExtension theme;
  final double level;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.glass : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: theme.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(16, (i) {
          final h = 10.0 + level * 56 * (0.45 + (i % 4) * 0.18);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                height: h,
                decoration: BoxDecoration(
                  color: AppColors.brandLight,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _MicHero extends StatelessWidget {
  const _MicHero({required this.theme});

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
              color: AppColors.brandLight.withValues(alpha: theme.isDark ? 0.14 : 0.1),
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
                  color: AppColors.brandGlow.withValues(alpha: 0.3),
                  blurRadius: 24,
                ),
              ],
            ),
            child: Icon(AppIcons.mic, size: 32, color: AppColors.brandLight),
          ),
        ],
      ),
    );
  }
}

class _TitleField extends StatelessWidget {
  const _TitleField({required this.theme, required this.controller});

  final WhisperThemeExtension theme;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.glass : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: theme.glassBorder),
      ),
      child: TextField(
        controller: controller,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: theme.foreground,
        ),
        decoration: InputDecoration(
          labelText: context.l10n.clipTitle,
          labelStyle: TextStyle(color: theme.muted, fontSize: 13),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
