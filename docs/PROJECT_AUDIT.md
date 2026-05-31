# WhisperBack — Veteran Product & Engineering Audit

**Date:** May 30, 2026  
**Auditor role:** Regional team lead (Product · UI/UX · Mobile · QA · Architecture)  
**Scope:** Phase 1 local MVP — `mobile/`, `design/`, `docs/`, CI, client deliverables  
**Overall maturity:** **Early MVP (≈45%)** — strong scaffold and design direction; critical execution gaps block client sign-off and store release.

---

## Executive Summary

WhisperBack has a coherent product vision, a premium v2 design language, and a reasonable Flutter architecture (feature folders + Riverpod + SQLite). However, the project is **not release-ready**. Several **P0 blockers** prevent compilation or runtime validation, core scheduling is **unwired**, playback behavior diverges from spec, and QA coverage is far below proposal commitments.

| Dimension | Score | Verdict |
|-----------|-------|---------|
| Product–spec alignment | 6/10 | Core flows exist; many spec details missing |
| UI/UX quality | 7/10 | v2 preview strong; Flutter lags preview; a11y gaps |
| Engineering quality | 5/10 | Good structure; broken imports, dead code, unwired scheduler |
| QA & testability | 3/10 | 3 tests total; CI likely red; no device matrix |
| Release readiness | 2/10 | No android/ios; no TestFlight/Play Internal |
| Documentation | 6/10 | Good specs; README overclaims vs reality |

**Recommendation:** Freeze new features for 2–3 weeks. Fix P0/P1 items below, complete client sign-off screens (S02, S04, S08, S13), then run QA checklist on real devices before Phase 2 cloud work.

---

## 1. Product Analysis

### What aligns with proposals

- Active/Inactive toggle (F-01) — UI + persistence
- Playlist CRUD scaffold (F-02) — partial
- Schedule builder + conflict detection (F-03) — engine + one unit test
- Per-playlist shuffle (F-04) — partial
- Sleep & Prayer modes (F-05) — duration + GPS prayer calc

### Critical product gaps

| Gap | Impact | Priority |
|-----|--------|----------|
| Scheduled playback never starts (`ScheduleEngine.start()` unwired) | Core value prop broken | P0 |
| Playback modal stops on close; only on Home | Violates spec; poor multitasking UX | P1 |
| Home shows **fake** quick stats (2, 30m, 5) | Misleading; erodes trust | P1 |
| Playlist limits (20/50) defined but not enforced | Premium model invisible | P2 |
| Global shuffle DB-only, no UI | Spec F-04 incomplete | P2 |
| No onboarding despite provider stub | First-run confusion | P2 |
| Cloud sync, admin, Cognito — stubs only | Expected for Phase 2 | P3 |

### Client sign-off status (required per `design/README.md`)

| Screen | Preview | Flutter | Signed off |
|--------|---------|---------|------------|
| S02 Home | ✅ | ⚠️ | ❌ |
| S04 Playlist detail | ✅ | ⚠️ missing rename/delete/add clips | ❌ |
| S08 Schedule builder | ❌ not in preview | ⚠️ no “next fire” preview | ❌ |
| S13 Playback modal | ✅ | ⚠️ behavior mismatch | ❌ |

---

## 2. UI/UX Design Audit

### Strengths

- `design/ui-preview.html` v2: glass surfaces, Fraunces + DM Sans, animated power toggle, bottom-sheet player
- `tokens.json` documents color, spacing, radius, animation
- Icon-first nav with optional labels matches spec
- Dark-first purple brand is distinctive and calm-app appropriate

### Weaknesses

| Issue | WCAG / spec | Fix |
|-------|-------------|-----|
| `muted` (#8B85A8) at 10–13px on deep bg | Likely fails AA contrast | Raise to ~#B8B3D0 for captions |
| Touch targets 32–42px on close, chips, nav | Spec min 44pt | Enforce 48dp minimum |
| Zero `Semantics` widgets | Screen reader blind | Add labels on icon-only controls |
| Sleep shortcut uses moon icon | Spec requires **Zzz** | Text chip “Zzz” on home |
| Preview covers 7/13 screens | Client can’t sign off full flow | Add S01, S06–S08, S11 |
| No light theme | Spec S12 promises toggle | Defer or document dark-only v1 |
| Fake home stats | UX honesty | Wire real data or remove |

---

## 3. Engineering Audit

### Architecture (good)

```
lib/
  core/       theme, router, shared widgets
  features/   screens by domain
  domain/     entities, playback enums
  data/       SQLite + repositories
  services/   audio, scheduler, prayer, shuffle
  providers/  Riverpod wiring
```

### P0 — Blockers

1. **Broken imports** in `repository_providers.dart` — wrong paths to `data/database` and `data/repositories`
2. **Broken imports** in `playback_providers.dart` — services under `services/` not `audio/`
3. **Missing `android/` and `ios/`** — `flutter create .` required; CI APK build fails
4. **Flutter SDK clone failed** — network error (`curl 18`); install via [flutter.dev](https://docs.flutter.dev/get-started/install) installer

### P1 — Critical logic gaps

1. `ScheduleEngine` never started — scheduled whispers never fire
2. `_shouldFire` uses fragile `second < 20` + 15s poll — missed/double fires
3. Sleep/prayer mode changes polled every 30s — up to 30s delay before pause
4. Demo seed uses `asset://demo/*.m4a` with no assets folder — playback fails on first run
5. `audio_service`, `permission_handler`, `flutter_local_notifications` in pubspec but unused
6. No background audio — playback stops when app backgrounded

### P2 — Code quality

- Playback progress hardcoded at 35% in modal
- Skip-previous button is no-op
- No clip completion → auto-next handling
- `AppPlaybackState.scheduledPlaying` never set
- `AppConstants` playlist limits never checked
- Clip delete doesn’t remove files from disk
- No DB migrations (`version: 1` only)
- `google_fonts` may fetch at runtime (offline risk)

---

## 4. QA Audit

### Current test inventory

| Test | File | What it covers |
|------|------|----------------|
| Shuffle cycle | `test/shuffle_engine_test.dart` | 1 scenario |
| Schedule conflict | `test/schedule_conflict_test.dart` | Overlap throws |
| Launch smoke | `integration_test/app_test.dart` | Finds “WhisperBack” text |

### Proposal vs reality

- Tech proposal: **70% coverage gate**, 80% logic modules
- CI: `flutter analyze`, `flutter test` only — **no integration tests in CI**
- `docs/qa-checklist.md`: 9 critical cases — **0 signed off**

### Missing test categories

- PlaybackCoordinator state machine
- ScheduleEngine fire windows
- Sleep/prayer priority over manual play
- Permission flows (mic, location)
- Widget/golden tests for sign-off screens
- Device matrix (Samsung, Xiaomi, iOS background limits)

---

## 5. Security & Privacy

| Area | Status |
|------|--------|
| Network / API | ✅ None in Phase 1 |
| Location | ⚠️ GPS on every prayer check; no rationale dialog |
| Audio storage | Local app docs; no encryption |
| Secrets in repo | ✅ None found |
| Orphan files on clip delete | ❌ Files remain on disk |
| Error messages | ⚠️ Raw exceptions shown to user |

---

## 6. Prioritized Remediation Roadmap

### Sprint A — Unblock (Week 1)

- [x] Fix provider import paths
- [x] Wire `ScheduleEngine.start()` on app bootstrap
- [x] Improve schedule fire deduplication
- [x] Playback modal: dismiss ≠ stop; mount in shell; real progress
- [x] Remove/wire home quick stats
- [x] Zzz sleep shortcut; clip filters; record permission prompt
- [ ] Run `flutter create .` in `mobile/`; verify analyze + test green
- [ ] Install Flutter SDK (official installer if git clone fails)

### Sprint B — Sign-off screens (Week 2)

- [ ] S04: rename, delete, add clips, delete guard when scheduled
- [ ] S08: “Next clip at HH:MM” preview; hour-based intervals
- [ ] S06: record timer + amplitude meter
- [ ] Expand `ui-preview.html` to all 13 screens
- [ ] Client review + checkboxes in `design/README.md`

### Sprint C — Release hardening (Week 3–4)

- [ ] `audio_service` background playback + lock screen
- [ ] `flutter_local_notifications` for schedule reliability
- [ ] Enforce playlist limits with soft messaging
- [ ] Expand tests to cover TC-01–TC-05, TC-08–TC-09
- [ ] Fastlane + TestFlight / Play Internal
- [ ] Sentry or equivalent crash reporting

### Phase 2 (post-MVP)

- AWS Cognito, DynamoDB, S3 sync
- Next.js admin panel
- IAP / subscription (v1.1 per monetization doc)

---

## 7. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| CI always red | High | Blocks team velocity | Fix imports + platform folders |
| Client rejects UI on sign-off | Medium | Rework | Complete S04/S08/S13 before review |
| Android OEM kills scheduler | High | Core feature fails | Battery whitelist guides + notifications |
| iOS schedule drift ±2 min | Medium | Expected | Document in Settings (already noted) |
| Demo clips unplayable | High | Bad first impression | Real placeholder audio or empty state |

---

## Appendix: File Reference

| Weak point | Primary files |
|------------|---------------|
| Broken imports | `lib/providers/repository_providers.dart`, `playback_providers.dart` |
| Scheduler unwired | `schedule_engine.dart`, `app.dart` |
| Fake home stats | `features/home/home_screen.dart` |
| Playback modal | `features/playback/playback_modal.dart`, `main_shell.dart` |
| Design preview gaps | `design/ui-preview.html` |
| QA checklist | `docs/qa-checklist.md` |
| CI | `.github/workflows/mobile_ci.yml` |

---

*This audit should be re-run after Sprint A completion and before client sign-off meeting.*
