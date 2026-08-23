# zlDeveloper conversation — prep sheet

Companion to [TECHNICAL_BRIEFING.md](TECHNICAL_BRIEFING.md). Part 1 explains every piece of the stack from zero. Part 2 is anticipated questions with answers. Part 3 is what to say when you genuinely don't know.

---

# Part 1 — The stack from zero

## The single most useful idea

Most of the technology in this app was **not chosen**. It is mandatory. If you build an Android app, you get Gradle. If you write Android native code, you write Kotlin or Java. If you use Flutter, you get Dart.

So when he asks "why did you use X?", the honest and correct answer for about half the stack is: *"That isn't a choice — it's what Android requires."* Knowing which items were real decisions and which were forced is the thing that will make you sound like you understand the project.


| Piece                              | Was it a choice?                                    |
| ---------------------------------- | --------------------------------------------------- |
| Flutter / Dart                     | **Yes** — cross-platform from one codebase          |
| Kotlin                             | No — the language Android native code is written in |
| Gradle                             | No — Android's build system, mandatory              |
| Java 17 / JVM target               | No — required by the current Android toolchain      |
| AndroidManifest                    | No — every Android app has one                      |
| Platform channels                  | No — the only way Flutter talks to native code      |
| `AlarmManager.setAlarmClock`       | **Yes** — chosen over 3 alternatives                |
| Native `MediaPlayer` for schedules | **Yes** — chosen over ExoPlayer                     |
| Riverpod                           | **Yes** — chosen over Bloc/Provider/GetX            |
| `sqflite`                          | **Yes** — chosen over Hive/Isar/Drift               |
| Xcode / CocoaPods / Swift          | No — Apple's mandatory toolchain                    |


---

## What is Flutter, and why does it need native code at all?

**Flutter** is Google's UI framework. You write the app once in **Dart**, and it compiles to a real native binary for Android and iOS. Unlike older cross-platform tools, Flutter draws every pixel itself rather than using the platform's UI widgets, which is why the app looks identical on both platforms.

But Flutter only covers the **UI and app logic**. It has no built-in access to platform-specific features like alarms, foreground services, or the microphone at OS level. For those you either use a plugin (someone else's native code, wrapped) or write the native code yourself.

WhisperBack needs exact alarms and a media foreground service. **No Flutter plugin does this correctly** (we tried `android_alarm_manager_plus` and it failed). So we wrote that part ourselves in native Android code.

## Why Kotlin?

Because Android native code is written in **Kotlin or Java**, and Kotlin has been Google's officially recommended language for Android since 2019. Java is legacy at this point. Every Android API — `AlarmManager`, `Service`, `MediaPlayer`, `BroadcastReceiver` — is a Java/Kotlin class. There is no way to call them from Dart directly.

So Kotlin was not a preference. It is the language of the platform we had to drop down into.

**Line to use:** "Kotlin is just what Android native code is written in. The Flutter/Dart side handles UI and scheduling logic; the Kotlin side owns AlarmManager and the playback service, because those are Android OS APIs that Dart can't reach."

## Why Gradle?

**Gradle** is Android's build system. It compiles the Kotlin, merges the manifest, bundles resources, links native libraries, and produces the APK. Every Android project uses it — there is no alternative.

What you *do* configure in Gradle:

- `minSdk 24` — the oldest Android version we support (Android 7.0, 2016). Lower means more devices but more compatibility code.
- `targetSdk 36` — the Android version we're built and tested against (Android 16). Play Store requires this to stay recent. Raising it opts you into new restrictions.
- `compileSdk 36` — which version of the Android APIs we compile against.
- **Java 17** — the JVM bytecode level. Required by the current Android Gradle Plugin.
- **Signing config** — the cryptographic key that identifies the app. **Ours is still the debug key, which is a release blocker.**

**Line to use:** "Gradle is mandatory for Android — it's the build system. What matters in ours is minSdk 24, targetSdk 36, and that release signing is still on the debug key, which we need to fix before Play."

## What is a platform channel?

The bridge between Dart and native code. Dart sends a named message with arguments; native code receives it, does the work, and returns a result. It's essentially a typed message bus across the language boundary.

We have three:


| Channel                         | Purpose                                                            |
| ------------------------------- | ------------------------------------------------------------------ |
| `com.whisperback.alarms`        | Push the schedule snapshot; pause/resume/stop; read playback state |
| `com.whisperback.keep_alive`    | Start/stop the keep-alive service                                  |
| `com.whisperback.clip_metadata` | Read an audio file's duration natively                             |


Communication goes both ways: native pushes playback state back to Dart via `onScheduledPlaybackState`.

## APK vs AAB

- **APK** — the installable Android app file. You can email it, sideload it, install it directly. This is what QA gets.
- **AAB (Android App Bundle)** — a publishing format that Google Play requires. Play generates optimised APKs per device from it.

We build APKs today. **We do not build an AAB yet**, which is a Play Store blocker.

## What is app signing?

Every Android app is cryptographically signed. The signature proves updates come from the same developer. Android refuses to install an update signed with a different key.

Flutter generates a **debug key** for development. Ours is still using it for release builds (there's a literal `TODO` in `build.gradle.kts`). Consequences:

- Cannot upload to Play
- Anyone could produce a "matching" build
- Users on the current debug-signed APK **cannot upgrade** to a future properly-signed build without uninstalling first

This is the number one thing to fix before launch.

## Why two audio players?

- **ExoPlayer** (via the `just_audio` package) — Google's modern, flexible player. Used for in-app manual playback.
- `MediaPlayer` — Android's older, simpler, built-in player. Used for scheduled playback.

We use `MediaPlayer` for schedules because the scheduled path runs inside a native Kotlin service with **no Flutter engine running**. `just_audio` is a Dart package — it needs the Flutter engine alive. `MediaPlayer` is a plain Android class with no dependencies, so it works from a cold-started service.

**Line to use:** "ExoPlayer for in-app playback, native MediaPlayer for scheduled playback — because the scheduled path runs with no Flutter engine alive, and a Dart package can't work there."

## The iOS toolchain

- **Xcode** — Apple's IDE and build toolchain. Only runs on macOS. Building for iPhone without a Mac is impossible.
- **CocoaPods** — the dependency manager for iOS native libraries. Flutter invokes it automatically.
- **Swift** — the iOS native language, the equivalent of Kotlin on Android.

Our `ios/` folder is a stock Flutter scaffold — no custom Swift, no platform channels. iOS compiles but has no scheduled playback.

---

# Part 2 — Questions and answers

## Architecture

**Q: What did you use for scheduling?**

> Native Android `AlarmManager.setAlarmClock()`. Dart projects the upcoming fire times into a JSON snapshot and passes it over a platform channel; Kotlin registers one exact alarm per fire. When one fires, a `BroadcastReceiver` starts a `mediaPlayback` foreground service that plays the clip with `MediaPlayer`. Flutter isn't involved in the fire path at all.

**Q: Why not just a Timer or a background isolate?**

> Three reasons. Doze mode defers ordinary background timers, sometimes by hours. `android_alarm_manager_plus` uses a background isolate, and a background isolate can't acquire audio focus on Android 14+, so the audio silently never plays — we shipped that and it failed. And `setAlarmClock` is the only API that's both Doze-exempt and grants a temporary background foreground-service-start allowance on Android 12+, which is what legally lets us start audio playback from a receiver.

**Q: Why not WorkManager?**

> Ten-minute minimum interval and it's deferred during Doze. Useless for "play at 7:00 PM exactly."

**Q: Isn't** `setAlarmClock` **abusive for a non-alarm app?**

> That's the fair challenge, and it's why we declare `USE_EXACT_ALARM` with a written justification. Our position is that scheduled playback at exact user-chosen times *is* the product — there's no meaningful app without it. If Play rejects that, we fall back to `SCHEDULE_EXACT_ALARM` with the runtime prompt; the code already catches the `SecurityException` and degrades to `setExactAndAllowWhileIdle`.

**Q: Why is there native Kotlin at all? Isn't Flutter supposed to avoid that?**

> Flutter covers UI and app logic. Exact alarms and foreground services are OS-level APIs with no adequate plugin. We tried the plugin route first and it didn't work, so we wrote roughly 2,000 lines of Kotlin across six files.

**Q: Why doesn't Dart fire schedules on Android?**

> It used to, and it caused a real bug. Both Dart and native would fire the same slot, producing two audio streams fighting over focus, and the Dart path would rebuild the alarm table mid-fire and cancel the next alarm. Now `ScheduleEngine._delegateFiringToNative` short-circuits the firing branch on Android. Dart still runs the engine for notification refresh and state polling — it just never plays.

## State and data

**Q: Why Riverpod over Bloc?**

> Compile-time safety, no `BuildContext` dependency, and easy provider composition. It's a small team and Bloc's event/state boilerplate wasn't buying us anything. If he prefers Bloc that's a reasonable position — the app's real complexity is in the native layer, not state management.

**Q: Are you using Riverpod code generation?**

> No. It's all the legacy declarative API — `Provider`, `FutureProvider`, `StreamProvider`, `StateNotifierProvider`. No `build_runner` anywhere in the project.

**Q: Why** `sqflite` **and not Hive/Isar/Drift?**

> Relational data with real foreign keys and cascading deletes — playlists to clips is many-to-many via a join table, and schedules cascade from playlists. `sqflite` is the standard, well-maintained SQLite binding. Drift would have given type-safe queries and is worth considering; we hand-write SQL today.

**Q: How do you test the database?**

> `sqflite_common_ffi` runs real SQLite on the desktop VM, so repository tests hit an actual database rather than a mock. A global test harness redirects the DB path to a per-isolate temp directory so parallel test files don't collide.

**Q: Where is audio stored?**

> On disk at `<app documents>/clips/<uuid>.m4a`, with the path in SQLite. A path guard rejects traversal attempts and anything outside the clips root, and an orphan sweep at startup deletes files with no database row.

## Audio

**Q: Why two audio engines?ll**

> ExoPlayer via `just_audio` for in-app playback, native `MediaPlayer` for scheduled playback. The scheduled path runs in a Kotlin service with no Flutter engine alive, so a Dart package can't be used there.

**Q: What was the silence keep-alive, and why is it disabled?**

> We looped an inaudible WAV through `audio_service` to keep the media foreground service bound and the process alive. It worked, but it fought the native `MediaPlayer` for audio focus and caused scheduled clips to auto-pause mid-play. It's now fully disabled on Android; a dedicated keep-alive service that plays no audio replaces it. It's still active on iOS.

**Q: Why does the app duck instead of pausing on audio focus loss?**

> Deliberate product decision. Samsung and Xiaomi fire transient focus loss for ordinary notifications, and the matching focus *gain* frequently never arrives, so the clip would sit paused forever. The rule is that a scheduled clip stops only on natural completion or an explicit user action. On focus loss we drop to 35% volume instead.

**Q:** `USAGE_MEDIA` **or** `USAGE_ALARM`**?**

> `USAGE_MEDIA` with `CONTENT_TYPE_MUSIC`. It was `USAGE_ALARM` originally, which routes through the alarm stream — always at 100% and unaffected by the media volume slider. Users complained the whispers were deafening. Media usage means the volume buttons work as expected.

## Build and release

**Q: What are your SDK versions?**

> `minSdk 24` (Android 7.0), `targetSdk 36` and `compileSdk 36` (Android 16). AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14, Java 17 with core library desugaring.

**Q: How is the app signed?**

> Right now, with the debug key — there's a `TODO` in `build.gradle.kts`. It's our top release blocker. We need a real keystore or Play App Signing before launch, and current QA builds won't upgrade cleanly to a properly signed build.

**Q: What does CI do?**

> Three GitHub Actions workflows. The main one enforces `dart format --set-exit-if-changed`, then `flutter analyze`, then the full test suite, then a debug APK build. A second builds release APKs split per ABI and uploads them as artifacts. A third compiles iOS unsigned on a macOS runner as a compile check.

**Q: Can I get an iOS build?**

> Not an installable one. CI produces an unsigned `Runner.app` that only proves it compiles. A real iOS build needs an Apple Developer account and TestFlight.

## Testing

**Q: What's your test coverage like?**

> 46 test files. Pure unit tests for the scheduling math and conflict detection, repository tests against real SQLite, some widget tests. The honest gap is that **the native scheduling path has zero automated coverage** — it's all manual device QA. That's the biggest risk in the project and something I'd like your view on.

**Q: What are these tests that read source files?**

> About 20 files read Dart or Kotlin source off disk and assert it contains certain strings. It's how we regression-guard native behaviour that can't run in the Dart VM — for example, asserting that `MainActivity` doesn't null the state listener in `onDestroy`. It's brittle: renaming a method or editing a comment can fail a test that never runs the code. I'd like your opinion on whether to keep them.

**Q: Why not Robolectric or instrumented tests?**

> Nobody set them up. That's exactly the kind of advice I'm after.

## Code quality

**Q:** `playback_coordinator.dart` **is 1,900 lines. Why?**

> It grew as the state machine absorbed each new edge case — native ownership routing, pause serialisation, auto-advance suppression, schedule stamping. It's past a comfortable size and I'd welcome a view on where to split it.

**Q: Why is localization a hand-written 2,000-line Dart class?**

> Speed at the time, and it's now technical debt. No ARB files, no `gen-l10n`, no way to detect a missing translation, and no workflow for a professional translator. Six languages are in there. Migrating to ARB is on my list.

**Q: Why so many comments referencing "Round 21", "Round 30"?**

> Each numbered round is a QA cycle. When we fixed a bug we recorded which report it addressed, which OEM it reproduced on, and why the obvious alternative was rejected — because several fixes look wrong without that context. Be aware some of those comments are asserted on by tests, so they're effectively load-bearing.

**Q: Do you have crash reporting?**

> No, and that's a gap. There's a global error handler that swallows to `debugPrint`, so in production those failures are invisible. Crashlytics or Sentry should go in before launch.

## Product edge cases

**Q: What if the user force-stops the app?**

> Nothing works until they reopen it. Android cancels every alarm for a force-stopped app. There's no workaround — it's an OS guarantee, not a bug.

**Q: What about OEM battery killers?**

> We request battery-optimisation exemption, and there's an in-app screen with per-OEM instructions for Samsung, Xiaomi, Oppo, Vivo, Realme, Infinix. Alarms are far more resilient than services on those devices, which is part of why the architecture leans on `AlarmManager` rather than a long-lived process.

**Q: How do you handle reboots?**

> A boot receiver listens for `BOOT_COMPLETED`, `LOCKED_BOOT_COMPLETED`, `QUICKBOOT_POWERON`, and `MY_PACKAGE_REPLACED`, then re-registers alarms from a stored snapshot — without launching Flutter.

**Q: What if an alarm arrives late?**

> Under 15 minutes late, it plays and logs the lateness. Over 15 minutes, we skip it, so a stale slot doesn't surprise the user hours later.

**Q: Timezone changes?**

> On app resume we force a full alarm rebuild, because the UI computes times from the current clock while the registered alarms hold fixed epoch timestamps.

---

# Part 3 — When you don't know

Do not bluff. A developer will spot it immediately, and it costs you credibility for the parts you *do* know. These responses are strong, not weak:

- "I don't know that one — can you explain what you'd expect there?"
- "That's outside what I've been across. What would you recommend?"
- "I know it works but not why it was done that way. Worth digging into together?"
- "Let me write that down and come back to you."

**Deflection that works when you're out of depth:**

> "I'm across the architecture and the decisions, but I'm not the one who wrote the code. What I'm really after is your view on whether the approach is sound and where the risks are."

That reframes the conversation from a quiz into a consultation, which is what you actually want.

## Your opening

> "It's a Flutter app, Android-first. The interesting part is that scheduled playback is entirely native Kotlin — `AlarmManager.setAlarmClock` into a media foreground service — because no Flutter plugin could do it reliably on Android 12+. Dart handles UI, the database, and computing when things should play. I want your read on whether the scheduling architecture is right, and how we'd get automated tests on the native path."

That signals in three sentences that you know what the app is, what the hard part is, and what you want from him.

## Your closing

Ask these before you finish:

1. Is `setAlarmClock` plus a `mediaPlayback` foreground service the right model on current Android?
2. How would you get automated coverage on the native scheduling path?
3. Are the source-level pinning tests defensible, or should they be replaced?
4. Will our `USE_EXACT_ALARM` justification survive Play review?
5. Beyond battery exemption and an in-app guide, what actually works against OEM killers?
6. Should `PlaybackCoordinator` be split, and where?
7. Is scheduled audio on iOS realistically achievable, or should we scope it out?
8. Would you migrate localization to ARB now or later?
9. What telemetry would you add to measure schedule accuracy in the field?

