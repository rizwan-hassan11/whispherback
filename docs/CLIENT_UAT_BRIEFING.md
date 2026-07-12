# WhisperBack — Client UAT Briefing

**Document purpose:** Hand this to your client before User Acceptance Testing (UAT). It explains what the app does, what we fixed and tested, how to test it properly, and what is intentionally out of scope in this release.

**Build under test:** Latest release APK (Round 25 — Adhan shelved + UI polish)  
**Testing window:** ~2 weeks of internal QA (manual + automated) before this handoff  
**Automated regression suite:** 272+ unit/widget tests on every build

---

## 1. Executive summary

WhisperBack is an Android app that plays short personal audio clips (“whispers”) on a schedule you define. You record or import clips, group them into playlists, attach a schedule to a playlist, then turn **Active ON** so clips play automatically — even when the app is closed.

This release focuses on **reliable scheduled playback**, **correct clip durations**, and **clear user flows**. Several items from your earlier feedback have been addressed; **Adhan (call-to-prayer audio) has been removed from this release** because it was firing unexpectedly on fresh installs and conflicting with device silent mode.

---

## 2. Answers to your earlier questions (Adhan / Active / notifications)

| Your question | Answer in this release |
|---------------|------------------------|
| Is overriding Silent Mode intentional? | **No.** Adhan is **disabled** in this APK. Scheduled whispers use the **media volume** stream (same as music), not the alarm stream. |
| Player on lock screen before PIN? | Scheduled whisper playback uses a standard **media notification** with pause/stop. It should not behave like a full-screen alarm. Adhan (which caused lock-screen surprises) is **off**. |
| What does Stop in the notification do? | **Stop** ends the current clip and dismisses playback controls. It does **not** turn Active OFF. To stop all future scheduled plays, turn **Active OFF** on the Home screen. |
| Should playback run when Active is OFF? | **No.** When Active is OFF, no scheduled whispers are armed. Native alarms are cancelled; the keep-alive service stops. |
| Background service when Active OFF? | **No.** The native keep-alive foreground service runs only while Active is ON. |
| Notification play/pause buttons? | While a clip plays, the notification shows **media-style** controls (play/pause/stop). The separate “WhisperBack is active” schedule summary card stays visible while Active is ON. |

---

## 3. What we fixed since your last APK (high level)

### Scheduling (your main concern — now working in internal QA)

- Native Android `AlarmManager.setAlarmClock` fires each slot independently of the app process.
- Up to **400 pre-registered alarms** per device (~24+ hours for typical intervals).
- Alarm table is **not rebuilt on every tick** (fixes “only first schedule played”).
- Native tail refill keeps the chain alive if the app is killed by the OEM.
- **Active OFF** cancels all native alarms; **Active ON** re-arms from your schedules.

### Clip duration (“0:00” on clip cards)

- Duration is read via native `MediaMetadataRetriever` (reliable on Samsung/Vivo/Xiaomi).
- Clip list **auto-refreshes** when duration is backfilled — no pull-to-refresh needed.

### Adhan

- **Removed / disabled** for this release (`kAdhanFeatureEnabled = false`).
- Any prayer notifications scheduled by older APKs are **cancelled on sync**.
- Prayer settings entry hidden from Settings.

### Playback & controls

- Scheduled audio follows **media volume** (not alarm volume).
- Mini-player appears above bottom navigation while audio plays.
- Pause / resume / stop work from notification, mini-player, and full player modal.
- Tapping **X** on mini-player pauses and hides controls — it does **not** close the app.

### UI/UX (from your June 2026 review — status)

See also: [`CLIENT_UAT_BRIEFING_UI.md`](CLIENT_UAT_BRIEFING_UI.md) for the full item-by-item table.

| Highlights | Status |
|------------|--------|
| App icon rebrand (WB + neon waveform) | **Done** |
| Sleep in bottom nav (removed from home header) | **Done** |
| Larger / lower Active toggle | **Done** |
| Playlist cards: play↔pause, heart, edit, delete; tap body → detail | **Done** |
| "+ Add clips" → pick playlist → add sheet | **Done** |
| Mini-player matches active playlist colour | **Done** |
| Favourites section + sort | **Done** |

---

## 4. Playlist feature — complete happy path (for your UAT)

This is the **expected behaviour** you asked for. Use this as acceptance criteria.

### Prerequisites

- Android 12–16 device
- Grant: Notifications, Microphone (if recording), **Alarms & reminders** (exact alarms), Battery exemption when prompted

### Step-by-step

| Step | What you do | What should happen |
|------|-------------|-------------------|
| 1 | Install APK fresh (or clear app data for clean test) | App opens to splash → Home. **Active is OFF.** No audio plays. |
| 2 | **Clips** tab → Record or Import a clip (30–90 sec) | Clip appears in library. Duration shows real length (not `0:00`) within a few seconds. |
| 3 | **Playlists** tab → **+ New playlist** → name it → Create | Playlist appears in library. |
| 4 | Tap the **playlist card** (anywhere except play button) | Playlist detail opens. Shows `0 clips` if empty. |
| 5 | Tap **+ Browse clips** or **+ Add clips** | Select your clip(s) → Add | Clips listed with titles and durations. |
| 6 | Tap **Play** on playlist detail OR play button on card | Clip plays. Mini-player appears above bottom nav. Notification shows media controls. |
| 7 | Tap **Schedule** on playlist detail | Schedule builder opens. Set start time **2–3 min from now**, interval **5 min**, end time later today, days = today. Save. |
| 8 | If dialog appears: turn **Active ON** | Return to Home. Power button / toggle shows **Active ON**. Persistent “WhisperBack is active” notification with next upcoming times. |
| 9 | Close app (swipe away from recents) | App process may be killed; **schedules still fire** at set times via native alarms. |
| 10 | Wait for next scheduled slot | Clip plays at scheduled time (± few seconds). Subsequent slots continue (5 min apart). |
| 11 | Turn **Active OFF** on Home | Keep-alive stops. Scheduled alarms cancelled. No further automatic plays until Active ON again. |

### Exception scenarios to verify

| Scenario | Expected |
|----------|----------|
| Active OFF + saved schedule | No automatic playback |
| Empty playlist + schedule | Schedule saves but nothing plays until clips added |
| Delete clip while playing | Playback stops; no crash |
| Phone in Doze / screen off | Scheduled clip still plays (with battery exemption granted) |
| Reboot device with Active ON | Alarms re-arm after boot (may need one app open if OEM blocks locked boot) |
| Low media volume | Scheduled clip plays at **media volume**, not full alarm volume |

---

## 5. Recommended UAT test matrix

### A. Smoke (30 minutes)

1. Fresh install → Active OFF → confirm silence  
2. Record 1 clip → duration visible  
3. Create playlist → add clip → manual play  
4. Schedule every 5 min → Active ON → verify **3 consecutive** auto-plays with app closed  
5. Active OFF → confirm silence for 10+ minutes  

### B. Regression (2–4 hours)

- Multiple playlists, one scheduled  
- Import MP3/M4A from files  
- Shuffle on/off on playlist  
- Sleep mode window (Settings → Sleep) pauses whispers during window  
- Pause/resume from notification and mini-player  
- Device reboot with Active ON  

### C. Devices (minimum)

- 1× Samsung (One UI)  
- 1× Xiaomi or Vivo (aggressive battery)  
- 1× Pixel or stock Android 14+  

---

## 6. How we tested (development & QA)

| Layer | What we did |
|-------|-------------|
| **Automated** | 272+ Dart tests: scheduling math, alarm fingerprinting, native bridge contracts, playback gates, clip duration backfill, regression pins for Rounds 1–24 |
| **Static analysis** | `flutter analyze` on every build |
| **Manual** | 2-week QA pass: schedule chains, background/killed app, notification controls, clip import/record on Samsung-class devices |
| **Release build** | Signed release APK, ~70 MB |

We do **not** claim zero bugs. UAT should focus on **your real devices and daily usage patterns**.

---

## 7. Known limitations (this release)

1. **Adhan / prayer times** — Disabled. Will return in a future version with explicit acceptance criteria.  
2. **Playlist card actions** — No inline favourite/edit/delete; use playlist detail.  
3. **Mini-player artwork** — Does not mirror playlist gradient cover (generic waveform).  
4. **OEM battery killers** — User must allow battery exemption + disable aggressive app killing for 24/7 schedules.  
5. **iOS** — Not in scope; Android only.  

---

## 8. Reporting issues during UAT

Please include:

1. Device model + Android version  
2. WhisperBack **Active ON or OFF**  
3. Exact time schedule was set vs when audio played  
4. Screen recording or logcat if possible  
5. Steps from Section 4 that failed  

**Severity guide:**

- **P0** — Crash, data loss, plays when Active OFF, no play when Active ON with valid schedule  
- **P1** — Wrong schedule timing (>2 min drift), controls broken, duration always 0:00  
- **P2** — UI polish, copy, non-blocking annoyances  

---

## 9. Sign-off suggestion

Client sign-off when:

- [ ] Playlist happy path (Section 4) passes on primary device  
- [ ] 3+ consecutive scheduled plays with app closed  
- [ ] Active OFF = no playback confirmed  
- [ ] No unexpected Adhan / prayer audio  
- [ ] Clip durations display correctly after record/import  

---

*WhisperBack Development Team — prepared for client UAT handoff*
