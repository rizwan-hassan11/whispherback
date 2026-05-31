import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return SharedPreferences.getInstance();
});

/// Supported app display languages (order: English, Urdu, French, Arabic, Dutch).
enum AppLanguage {
  english('en', 'English'),
  urdu('ur', 'Urdu'),
  french('fr', 'French'),
  arabic('ar', 'Arabic'),
  dutch('nl', 'Dutch');

  const AppLanguage(this.code, this.label);

  final String code;
  final String label;

  Locale get locale => Locale(code);

  /// Native script shown under the English label in the picker.
  String get nativeScript => switch (this) {
        AppLanguage.english => 'English',
        AppLanguage.urdu => '\u0627\u0631\u062F\u0648',
        AppLanguage.french => 'Fran\u00E7ais',
        AppLanguage.arabic => '\u0627\u0644\u0639\u0631\u0628\u064A\u0629',
        AppLanguage.dutch => 'Nederlands',
      };

  static AppLanguage fromCode(String? code) {
    return AppLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguage.english,
    );
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(AppLanguage.english.locale) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('app_locale');
    if (code != null) {
      state = AppLanguage.fromCode(code).locale;
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = language.locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_locale', language.code);
  }
}

final showLabelsProvider = StateNotifierProvider<ShowLabelsNotifier, bool>((ref) {
  return ShowLabelsNotifier();
});

enum AppThemeMode { dark, light, system }

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, AppThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<AppThemeMode> {
  ThemeModeNotifier() : super(AppThemeMode.dark) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('theme_mode') ?? 'dark';
    state = AppThemeMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => AppThemeMode.dark,
    );
  }

  Future<void> setMode(AppThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }
}

class ShowLabelsNotifier extends StateNotifier<bool> {
  ShowLabelsNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('show_labels') ?? false;
  }

  Future<void> toggle(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_labels', value);
  }
}

final firstLaunchProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('onboarding_complete') != true;
});

Future<void> completeOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('onboarding_complete', true);
}

final defaultAlarmProvider = StateNotifierProvider<DefaultAlarmNotifier, bool>((ref) {
  return DefaultAlarmNotifier();
});

final defaultIntervalProvider = StateNotifierProvider<DefaultIntervalNotifier, int>((ref) {
  return DefaultIntervalNotifier();
});

class DefaultAlarmNotifier extends StateNotifier<bool> {
  DefaultAlarmNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('default_alarm') ?? true;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('default_alarm', value);
  }
}

class DefaultIntervalNotifier extends StateNotifier<int> {
  DefaultIntervalNotifier() : super(30) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt('default_interval') ?? 30;
  }

  Future<void> set(int value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('default_interval', value);
  }
}
