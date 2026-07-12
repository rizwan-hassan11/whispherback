import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/playback/mini_player_bar.dart';
import '../../features/playback/playback_modal.dart';
import '../../domain/playback/playback_state.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/playback_providers.dart';
import '../../services/playback/playback_coordinator.dart';
import '../layout/shell_messenger.dart';
import '../layout/responsive.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'adaptive_shell_nav.dart';
import 'audio_service_warning_banner.dart';
import 'glass_nav_bar.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  String? _lastLocation;
  StreamSubscription<PlaybackErrorEvent>? _errorSub;

  @override
  void initState() {
    super.initState();
    // Subscribe to playback failures so every play tap gets feedback — a
    // silent no-op was the root cause of the client report "tried to play my
    // recording, nothing happened". Deferred to the next frame so the
    // ScaffoldMessenger is mounted before the first event is dispatched.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _errorSub =
          ref.read(playbackCoordinatorProvider).errors.listen(_onPlaybackError);
    });
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    super.dispose();
  }

  void _onPlaybackError(PlaybackErrorEvent event) {
    if (!mounted) return;
    final l10n = context.l10n;
    final message = switch (event.reason) {
      PlaybackErrorReason.pathRejected => event.clipTitle == null
          ? l10n.playbackClipUnavailable
          : l10n.playbackClipUnavailableNamed(event.clipTitle!),
      PlaybackErrorReason.decodeFailed => event.clipTitle == null
          ? l10n.playbackClipFailed
          : l10n.playbackClipFailedNamed(event.clipTitle!),
      PlaybackErrorReason.emptyPlaylist => l10n.playbackEmptyPlaylist,
      PlaybackErrorReason.inactiveToggle => l10n.playbackInactiveToggle,
    };
    context.showShellSnackBar(message, icon: AppIcons.alertCircle);
  }

  static List<GlassNavDestination> _destinations(BuildContext context) {
    final l10n = context.l10n;
    return [
      GlassNavDestination(
        icon: AppIcons.home,
        selectedIcon: AppIcons.home,
        label: l10n.navHome,
      ),
      GlassNavDestination(
        icon: AppIcons.playlists,
        selectedIcon: AppIcons.playlists,
        label: l10n.navLists,
      ),
      GlassNavDestination(
        icon: AppIcons.mic,
        selectedIcon: AppIcons.mic,
        label: l10n.navClips,
      ),
      GlassNavDestination(
        icon: AppIcons.schedule,
        selectedIcon: AppIcons.schedule,
        label: l10n.navSchedule,
      ),
      GlassNavDestination(
        icon: AppIcons.settings,
        selectedIcon: AppIcons.settings,
        label: l10n.navSettings,
      ),
    ];
  }

  int _indexForLocation(String location) {
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/playlists')) return 1;
    if (location.startsWith('/clips')) return 2;
    if (location.startsWith('/schedule')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }

  void _go(BuildContext context, int i) {
    switch (i) {
      case 0:
        context.go('/home');
      case 1:
        context.go('/playlists');
      case 2:
        context.go('/clips');
      case 3:
        context.go('/schedule');
      case 4:
        context.go('/settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (_lastLocation != null && _lastLocation != location) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(playbackCoordinatorProvider).dismissModal();
      });
    }
    _lastLocation = location;

    final index = _indexForLocation(location);
    final theme = whisperTheme(context);
    final r = context.responsive;
    final playback = ref.watch(playbackSnapshotProvider);
    final snapshot = playback.valueOrNull;
    final miniPlayerVisible = snapshot != null &&
        snapshot.state != AppPlaybackState.inactive &&
        snapshot.state != AppPlaybackState.activeIdle &&
        snapshot.playlistName != null &&
        !snapshot.modalVisible;
    final shellBottomReserve = ShellMetrics.reservedBottomHeight(
      context,
      miniPlayerVisible: miniPlayerVisible,
    );

    final body = LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: r.hingePadding,
          child: SizedBox(
            height: constraints.maxHeight,
            width: constraints.maxWidth,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: r.contentMaxWidth,
                        minHeight: constraints.maxHeight,
                        maxHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const AudioServiceWarningBanner(),
                          Expanded(
                            child: MediaQuery.removePadding(
                              context: context,
                              removeBottom: true,
                              child: Padding(
                                padding:
                                    EdgeInsets.only(bottom: shellBottomReserve),
                                child: widget.child,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const PlaybackModal(),
              ],
            ),
          ),
        );
      },
    );

    final bottomBar = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: r.horizontalGutter),
          child: const MiniPlayerBar(),
        ),
        GlassNavBar(
          showAllLabels: theme.showLabels,
          selectedIndex: index,
          onSelected: (i) => _go(context, i),
          destinations: _destinations(context),
        ),
      ],
    );

    if (r.useSideNavigation) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              right: false,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                child: AdaptiveShellNav(
                  showAllLabels: theme.showLabels,
                  selectedIndex: index,
                  onSelected: (i) => _go(context, i),
                  destinations: _destinations(context),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: r.hingePadding.left > 0 ? 0 : 4,
                  right: r.hingePadding.right,
                ),
                child: body,
              ),
            ),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.symmetric(horizontal: r.horizontalGutter),
          child: const MiniPlayerBar(),
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: body,
      bottomNavigationBar: bottomBar,
    );
  }
}
