# Baseline Ring — Weekend MVP Build Plan

The `oura-parity` branch adds readiness, sleep score, activity load, a non-diagnostic multi-day pattern flag, and day tags on top of this plan. Those scores stay explainable z-scores. Do not replace `BaselineEngine`. Hardware limits and what is still unverified are in `OURA_PARITY.md` and the README hardware table. The schedule below is the original weekend sequence.

**Owner:** Zabir Islam
**Repo:** https://github.com/Zabir210/Baseline-Ring
**Stack:** SwiftUI, HealthKit, SwiftData, WidgetKit, App Intents, Swift Charts, watchOS SwiftUI
**North star:** On-device personal baselines and an explainable “your pattern broke” alert. Not a Whoop clone.

The scaffold on `main` already contains the Xcode project, `BaselineCore`, the z-score engine and tests, a read-only HealthKit reader, the iPhone shells, the Watch status screen, one complication, and `AmIOffBaselineIntent`. Use the schedule below for what is still left, not to recreate the project.

**App Group:** `group.com.zabir.baselinering`
**iOS bundle:** `com.zabir.baselinering`
**Watch bundle:** `com.zabir.baselinering.watchkitapp`

iPhone and Watch use that same group id and **separate containers**. The iPhone pushes `BaselineSnapshot.json` over WatchConnectivity; the Watch writes its own copy for the complication. Do not spend Saturday debugging a shared filesystem that does not exist.

---

## Scaffold status

| Block | State on `main` |
|---|---|
| S0 Repo + targets | Done. Open `BaselineRing.xcodeproj`. |
| S1 SwiftData models | Done, including an in-memory test. |
| S2 HealthKit reader | Read path is implemented (auth + 60-day aggregate). Confirm counts on a simulator or phone. |
| S4 BaselineEngine | Done. Bessel σ, epsilon floors, learning under 10 days, direction rules, settings. |
| S5 Alert copy | Templates and direction tests are in Core. |
| S6 iPhone shell | Today, detail sparkline, alerts, settings, permission button, example pattern. |
| U1 Dashboard | Shell is in place. Tighten it on device. |
| U2 Watch | Status list + manual refresh. Depends on the snapshot push. |
| U4 Complication | Timeline provider reads the Watch snapshot. |
| U5 App Intent | `AmIOffBaselineIntent` in `BaselineRingIntents`. Confirm it appears in Shortcuts. |
| U6 Background delivery | Not wired. `enableBackgroundUpdates()` is an empty stub. |
| U7 README | This repo’s `README.md`. |

---

## 1. Product brief + non-goals

**Brief.** Baseline Ring learns HealthKit baselines for HRV, resting heart rate, sleep duration, and steps, then flags when a day breaks that personal pattern. Detection is rolling mean/σ, with optional CUSUM, fully on-device. The Watch complication is a one-glance status. The iPhone shows the value, μ, σ, z, and plain-English “why” copy. One Shortcut answers “Am I off baseline?”

**Non-goals (do not build this weekend):**

- Training load, strain, recovery scores, or any Whoop/Oura-style composite index
- Cloud sync, accounts, analytics SDKs, or server-side models
- Menstrual cycle, SpO₂, respiratory rate, ECG, workouts as first-class metrics
- Social, sharing, coaching chat, or LLM narratives
- Menubar Pulse / macOS / Shortcut Signal Pack
- Marketing UI polish, onboarding animations, paywall
- App Store submission (checklist only — section 7)

---

## 2. Architecture

| Target / module | Role |
|---|---|
| `BaselineRing` (iOS) | Permissions, dashboard, alert history, settings |
| `BaselineRingWatch` (watchOS) | Glance status, refresh, snapshot from the iPhone |
| `BaselineRingWidgets` | One Watch complication |
| `BaselineRingIntents` | `AmIOffBaselineIntent` |
| `BaselineCore` (local package) | Models, engine, copy, snapshot file, SwiftData store. No UI |

Apps / widgets / intents → `BaselineCore`. HealthKit and WatchConnectivity stay in the app targets so the widget can link Core with extension-only APIs.

Shared files, each in its own device container:

- SwiftData store `BaselineRing.store` (CloudKit **off**)
- `BaselineSnapshot.json` for the complication and the Shortcut

```
HealthKit ──► HealthKitReader ──► DailyMetric (SwiftData)
                                      │
                                      ▼
                               BaselineEngine (21-day window)
                                      │
                                      ▼
                               z-score, optional CUSUM
                                      │
                                      ▼
                         AnomalyAlert + BaselineSnapshot.json
                                      │
                          WatchConnectivity ──► Watch container
                                      │
                                      ▼
                              complication timeline
```

Background (Sunday): `HKObserverQuery` + `enableBackgroundDelivery` for the four types, debounced into one recompute. No ML.

---

## 3. Data model (SwiftData)

Already in `BaselineCore`.

### MetricSample

`id`, `metric` (`hrv` / `rhr` / `sleep` / `steps`), `startDate`, `endDate`, `value`, `sourceBundleId?`, `importedAt`.

The MVP dashboard uses daily aggregates. Raw samples are for provenance; step samples are not stored one-by-one.

### DailyMetric

`id`, `day` (local start of day), `metric`, `value`, `sampleCount`.

Aggregation: HRV daily mean (ms), RHR daily mean (bpm), sleep asleep hours, steps daily sum.

### BaselineState

`metric`, `windowDays` (14…30, default 21), `mean`, `stddev` (floored), `sampleCount`, `updatedAt`, `cusumPos`, `cusumNeg`.

### AnomalyAlert

`id`, `metric`, `day`, `observed`, `baselineMean`, `zScore` (signed), `severity` (`info` / `warn` / `high`), `message` (frozen at write time), `acknowledged`, `createdAt`.

One row per metric per day. A stronger z replaces the message and clears the acknowledgement.

### AppSettings

`baselineWindowDays` 21, `zWarn` 2.0, `zHigh` 3.0, `cusumEnabled` false, `notificationsEnabled`, `lastRefreshAt`, plus `didRequestHealthAccess` and `usingExamplePattern` so cold start and the example series are explicit.

**HealthKit types (read only):**

| Metric | HK type | Day value |
|---|---|---|
| HRV | `heartRateVariabilitySDNN` | Mean ms |
| RHR | `restingHeartRate` | Mean bpm |
| Sleep | `sleepAnalysis` | Asleep hours for the wake day. Ignore in-bed-only. Prefer `.asleep*` stages. |
| Steps | `stepCount` | Sum |

Ignore the unfinished current day for steps and sleep. HRV and RHR may update when new samples arrive.

---

## 4. Anomaly logic

Implemented in `BaselineEngine` and `BaselineRefreshJob`.

- Metrics: all four, same detector family.
- Window: 21 days, user choices 14 / 21 / 30. Under 10 baseline days → status **Learning**, no z, no alert.
- σ is the sample standard deviation (Bessel, n−1), then `max(σ, ε)` with ε = 1 ms, 0.5 bpm, 0.15 h, 500 steps.
- `z = (x − μ) / σ`. μ and σ do not include the observation day.
- HRV ↓ and sleep ↓ alert on negative z. RHR ↑ alerts on positive z. The favorable direction stays in range.
- `|z| ≥ zWarn` (2) → warn. `|z| ≥ zHigh` (3) → high.
- Steps ↓ are info once `|z| ≥ zWarn`, warn at `z ≤ −2.5`, high at `zHigh`. More steps than usual is not an alert.
- CUSUM stretch: one-sided on the bad direction, `k = 0.5`, `h = 4` in z units. Off unless `cusumEnabled`. A trip raises the status to warn if z-score has not already.

**Copy** (numbers filled in, no medical claims):

- HRV: “Your HRV is **{value} ms**, about **{abs_z}σ below** your {W}-day average of **{μ} ms**. That breaks your usual range.”
- RHR: “Resting HR is **{value} bpm**, **{abs_z}σ above** your baseline **{μ} bpm**.”
- Sleep: “Last night you slept **{value} h** vs baseline **{μ} h** ({abs_z}σ low).”
- Steps: “Steps are light today: **{value}** vs usual **{μ}** ({abs_z}σ below).”

Footer on alert UI: “Personal pattern signal — not a diagnosis.”

Local notification only on a new warn/high or a severity upgrade, and only if notifications are enabled.

---

## 5. Sat–Sun schedule

Protect sleep. No heroics past midnight. The blocks below are the original weekend sequence; skip work the scaffold already covers and use the time on device confirmation.

### Saturday — Foundation + data path

| Block | Milestone | Done when |
|---|---|---|
| S0 | Repo + targets | Open the existing project. Signing team set. App Group noted. |
| S1 | Models | `swift test` or Product → Test passes `testInMemoryModelsRoundTrip`. |
| S2 | HealthKit | Authorize the four types. Pull history. Debug or Today shows day counts. |
| S3 | Break | |
| S4 | Engine | Hand-calc test still matches. Learning under 10 days. Sensitivity changes the status. |
| S5 | Copy | HRV↓ and RHR↑ tests pass. Strings match the templates. |
| S6 | iPhone shell | Today, settings, permission button. Example pattern shows a high HRV break. |

**Sat exit:** Authorize → import → see μ/σ/z, or the example series if Health is empty.

### Sunday — Surfaces

| Block | Milestone | Done when |
|---|---|---|
| U0 | Recap | Refresh recomputes. Saturday bugs closed. |
| U1 | Dashboard | Four cards, sparkline, acknowledge. |
| U2 | Watch | All-clear or the driving break. Snapshot arrives from the iPhone. |
| U3 | Break | |
| U4 | Complication | Circular or corner: green / amber / red from the worst severity. Timeline reloads after the Watch writes the snapshot. |
| U5 | App Intent | Shortcut returns “All clear” or the top sentence, plus the footer. |
| U6 | Background delivery | Observer query + `enableBackgroundDelivery` for the four types. Debounce. Confirm one update on device. This needs the HealthKit background-delivery entitlement; it is intentionally not in the stub entitlements. |
| U7 | Dogfood + README | Note gaps. Tag `mvp-weekend` when the exit criteria below are true. |

**Sun exit:** Complication matches severity. Shortcut answers. iPhone explains one live or example anomaly in plain English. Cold start with no Health permission shows Learning and does not crash.

---

## 6. Screens

### iPhone

1. **Permissions** — why HealthKit, the four metrics, request button, “on-device only”.
2. **Today** — four cards, overall status, pull to refresh.
3. **Metric detail** — sparkline, μ/σ, latest z, recent alerts.
4. **Alerts** — list, severity, acknowledge.
5. **Settings** — window 14/21/30, z thresholds, notifications, rebuild, example pattern, disclaimer.

### Watch

1. **Status** — overall line and one row per metric. Refresh asks the iPhone for the latest snapshot.

### Complication

Circular or graphic circular. Letter H/R/S/T for the driving metric, `OK` when in range, `–` while learning. Corner is the fallback and is already a supported family.

### Shortcut

“Am I off baseline?” reads the snapshot. No extra UI.

---

## 7. App Store / privacy checklist (not a weekend blocker)

- [ ] App ID with HealthKit. Watch + widget + intents + App Group. Background modes only when U6 lands.
- [ ] Nutrition labels: Health data yes. Tracking no. Data not linked and not used to track.
- [ ] `NSHealthShareUsageDescription` is present. Do not add an update string unless the app starts writing.
- [ ] Privacy policy URL: on-device, no account, no sale, which HK types, retention until delete.
- [ ] Review notes in fitness/education framing. No diagnostic claims.
- [ ] “Not medical advice” in the description and first run.
- [ ] No third-party analytics. Health-adjacent data lives in the App Group.
- [ ] No accounts, so no account-deletion flow. Say that.
- [ ] TestFlight, age rating, export compliance when you actually ship.

---

## 8. Stretch (only after U5)

1. Lock Screen rectangular widget.
2. CUSUM toggle in Settings (the math is already in Core).
3. Notification “Acknowledge” action.
4. The example pattern is already a Settings button. A review/demo mode can reuse it.
5. CSV export of `DailyMetric` via ShareLink. Still on-device.

Skip Menubar Pulse and the Signal Pack.

---

## 9. After the weekend

1. Internal TestFlight to the phone and Watch. Install the complication on a real face.
2. Two weeks of dogfood: days with a real baseline, alert rate (rough hope: under one high per week unless the week was genuinely unusual — tune z if it is noisy), a three-line note when an alert feels wrong, whether the morning glance was useful, and whether `lastRefreshAt` stays fresh.
3. Local-only counters for refreshes, auth failures, and empty days. A debug screen, not a vendor SDK.
4. Pick the next slice from the false-positive notes: notification quality, demo mode, or a second complication.
5. Keep the `BaselineCore` snapshot shape stable.

---

## Working style

Prefer boring, defensible math. Show μ, σ, and z on the detail screen. Fail closed on claims: pattern language only. If sleep stages are messy, ship duration and write down the gap. If the widget cannot open SwiftData, the JSON snapshot is the complication source of truth — that is already how it works. Ship Sunday with sharp edges rather than Monday with half a prettier app.

**Weekend definition of done:** real device, four baselines, explainable alerts, one complication, one Shortcut, README, `mvp-weekend` tag.
