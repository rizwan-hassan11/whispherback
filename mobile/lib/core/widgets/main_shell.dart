import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/playback/playback_modal.dart';
import '../../l10n/app_localizations.dart';
import '../layout/responsive.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'adaptive_shell_nav.dart';
import 'glass_nav_bar.dart';
import 'glass_side_nav.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

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
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    final index = _indexForLocation(location);
    final theme = whisperTheme(context);
    final r = context.responsive;

    final body = Padding(
      padding: r.hingePadding,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: r.contentMaxWidth),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              const PlaybackModal(),
            ],
          ),
        ),
      ),
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
      );
    }

    return Scaffold(
      extendBody: true,
      body: body,
      bottomNavigationBar: GlassNavBar(
        showAllLabels: theme.showLabels,
        selectedIndex: index,
        onSelected: (i) => _go(context, i),
        destinations: _destinations(context),
      ),
    );
  }
}
