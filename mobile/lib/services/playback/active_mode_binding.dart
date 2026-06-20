typedef ActiveStopCallback = Future<void> Function();

/// Lets notification actions reach playback state without Riverpod.
class ActiveModeBinding {
  ActiveModeBinding._();

  static final ActiveModeBinding instance = ActiveModeBinding._();

  ActiveStopCallback? _stopActive;

  void attach(ActiveStopCallback stopActive) => _stopActive = stopActive;

  void detach() => _stopActive = null;

  Future<void> stopActive() async {
    await _stopActive?.call();
  }
}
