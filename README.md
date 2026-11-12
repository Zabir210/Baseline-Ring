# Baseline Ring

Privacy-first iPhone and Apple Watch app: Oura-style insights from the Apple Watch you already own. No ring and no subscription. Readiness, sleep, and activity load are weighted z-scores on top of the same on-device baseline engine. Every score lists which metrics moved it and by how many standard deviations. When there is not enough fresh data, the app says so instead of showing a number.

Data stays on the devices. The SwiftData store is created with CloudKit disabled.

## Non-goals

- Cloud sync, accounts, analytics SDKs, or server-side models
- A medical or diagnostic claim. Copy stays “your pattern changed” / “personal pattern signal — not a diagnosis.”
- Menstrual cycle, SpO₂, respiratory rate, or ECG as first-class metrics
- Social, sharing, coaching chat, or LLM narratives
- macOS menu bar, or a Shortcut signal pack
- Marketing polish, onboarding animations, or a paywall
- App Store submission (the checklist lives in `WEEKEND_BUILD_PLAN.md`)

UI copy stays in pattern language. The standing footer is “Personal pattern signal — not a diagnosis.”

## What’s already in the repo

| Piece | Where |
|---|---|
| iOS app (Today, detail, alerts, settings) | `BaselineRing/` |
| watchOS status screen | `BaselineRingWatch/` |
| Watch complication (WidgetKit) | `BaselineRingWidgets/` |
| “Am I off baseline?” App Intent | `BaselineRingIntents/` |
| Models, z-score engine, alert copy, snapshot | `BaselineCore/` (local Swift package, no UI) |
| HealthKit read path (HRV, RHR, sleep, steps, active energy, workouts, wrist temperature when present) | `BaselineRing/Health/HealthKitReader.swift` |
| Readiness, sleep score, activity load, pattern-change flag, tag effects | `BaselineCore/Sources/BaselineCore/Scores/` |
| Engine tests | `BaselineCore/Tests/BaselineCoreTests/` |

The feature map and the gaps are in `OURA_PARITY.md`.

Still for the weekend, not this scaffold: `HKObserverQuery` background delivery, notification categories, and real-device dogfood. See the schedule in `WEEKEND_BUILD_PLAN.md`.

## Requirements

- Mac with Xcode 16 or newer (the project uses synchronized folder groups)
- The app target is iOS 17 and watchOS 10. That is the lowest SwiftData allows, and watchOS 10 is the last system Apple Watch Series 4 can run. See the hardware table below.
- A development team selected in Signing & Capabilities
- A paid Apple Developer Program membership to run HealthKit on a physical iPhone. The simulator can run without the paid program once a personal team is selected, but Health samples in the simulator are usually empty — use **Settings → Load example pattern**

## Hardware support

The build cannot drop to iOS 16 or watchOS 8. SwiftData, the SwiftUI observation used by the screens, and the watch app’s widget embedding need iOS 17 and watchOS 10. Series 4’s newest system is watchOS 10, so that watch is in range. Features that depend on newer sensors are skipped when the data is absent. They are not filled in with a fake number.

| Feature | Series 4 on watchOS 10 | Series 6–7 | Series 8, Ultra, and later | If the data is missing |
|---|---|---|---|---|
| HRV, resting HR, steps | Yes. HRV is often sparse, so confidence stays medium or the score is withheld until 10 fresh days. | Yes | Yes | “Not enough data” |
| Sleep duration, in-bed, efficiency, bedtime consistency | Yes | Yes | Yes | Duration-only, or no sleep score under 10 nights |
| Core / deep / REM | When Health has stage samples (recordings from watchOS 9+). The API is gated with `#available(iOS 16, *)`. | Yes | Yes | Fallback path. No stage points. |
| Active energy | Yes | Yes | Yes | Load uses whatever of steps, energy, and zone minutes exists |
| Workout heart-rate minutes | Estimated from workout average HR (full credit at ≥120 bpm, half at 100–119). Not a clinical zone model. | Yes | Yes | Zone term omitted |
| Wrist temperature | No sensor | No sensor | `appleSleepingWristTemperature` when samples exist (`#available(iOS 16, *)`) | Pattern-change flag does not require it |
| Readiness on the Watch complication | watchOS 10 WidgetKit. Shows the number, or “–” when confidence is low. | Yes | Yes | “–” |
| iOS 16 phone / watchOS 8–9 | Not a supported build. A paired Series 4 on watchOS 10 needs an iPhone that can run iOS 17. | — | — | — |

## Clone and open on a Mac

```bash
git clone https://github.com/Zabir210/Baseline-Ring.git
cd Baseline-Ring
open BaselineRing.xcodeproj
```

SSH, if that’s how this machine talks to GitHub:

```bash
git clone git@github.com:Zabir210/Baseline-Ring.git
```

Wait until Xcode finishes resolving the local `BaselineCore` package (it has no remote dependencies). Select the **BaselineRing** scheme and an iPhone simulator. Press Run.

The shared schemes are **BaselineRing** (iPhone, builds the Watch app, complication, and intents extension) and **BaselineRingWatch**.

### Claude Code

Open this folder in Claude Code after the clone. Point it at `WEEKEND_BUILD_PLAN.md` and this README. The math to defend is in `BaselineCore`; the shells are the four targets above. Keep new strings free of medical claims, and do not add a backend.

```bash
cd Baseline-Ring
claude
```

## Signing, HealthKit, and the App Group

Bundle IDs:

| Target | Bundle ID |
|---|---|
| BaselineRing | `com.zabir.baselinering` |
| BaselineRingWatch | `com.zabir.baselinering.watchkitapp` |
| BaselineRingWidgets | `com.zabir.baselinering.watchkitapp.widgets` |
| BaselineRingIntents | `com.zabir.baselinering.intents` |

App Group placeholder, already in every entitlement file:

`group.com.zabir.baselinering`

On a physical device, create that group and turn on the capabilities for the App IDs:

1. Xcode → each target → Signing & Capabilities → Team.
2. iOS target: **HealthKit** (read-only; the app never requests write access) and **App Groups**.
3. Watch, widget, and intents targets: **App Groups**, same group id.
4. In the developer portal, the iOS App ID needs HealthKit. Add the App Group to all four App IDs if automatic signing does not do it.

`NSHealthShareUsageDescription` is set. There is no `NSHealthUpdateUsageDescription`, because the app does not write Health samples.

If signing fails with a missing entitlement, the portal capability and the `.entitlements` file disagree. Simulator builds often succeed with only a personal team; device builds need the capabilities registered.

The iPhone and the Watch do **not** share one App Group folder. The iPhone writes `BaselineSnapshot.json`, then `PhoneWatchLink` pushes it with WatchConnectivity. The Watch writes its own copy so the complication can read it. Same group id on both targets, separate containers.

If the App Group entitlement is missing, the iPhone falls back to Application Support and Settings explains that. The app still launches.

## Run

1. Run the iOS app.
2. Tap **Allow Health Access**, or open **Settings → Load example pattern** to see alert copy without Health data. The example banner says the numbers are not your health data.
3. Today shows four cards: value, baseline mean, z-score, and a status chip. Pull to refresh.
4. A metric needs 10 days before it leaves **Learning**. The default window is 21 days (14 or 30 in Settings).
5. Alerts can be acknowledged. The footer stays on Today, Alerts, and Settings.
6. Run the Watch scheme (paired simulator or a real Watch) and tap Refresh. The complication glyph is `OK`, `–`, or H/R/S/T for the strongest break. Color follows severity: green, gray, blue, orange, red.

The shortcut **Am I Off Baseline?** is the `AmIOffBaselineIntent` in the intents extension. It reads the on-device snapshot and answers in text. It does not open the app.

## Tests

In Xcode: scheme **BaselineRing**, Product → Test. That runs `BaselineRingTests`, which compile the package tests.

On a Mac, without a simulator:

```bash
cd BaselineCore
swift test
```

The engine tests lock a hand calculation (Bessel sample σ, epsilon floors, HRV down vs resting HR up, the steps info/warn/high bands, and the example series).

## Layout

```
BaselineRing.xcodeproj/          open this
BaselineCore/                    Swift package, no SwiftUI
  Sources/BaselineCore/          models, BaselineEngine, copy, snapshot, store
  Tests/BaselineCoreTests/
BaselineRing/                    iOS app
BaselineRingWatch/               watchOS app
BaselineRingWidgets/             complication
BaselineRingIntents/             App Intents extension
project.yml                      optional XcodeGen spec; do not regenerate casually
WEEKEND_BUILD_PLAN.md            hour-by-hour plan
```

Dependency direction: apps, widgets, and intents → `BaselineCore` → Foundation / SwiftData. HealthKit and WatchConnectivity stay in the app targets so the widget and intents extension can link Core with extension-safe APIs.

### Detector (already implemented)

- Window default **21** days, clamped to 14…30. Alerting starts at **10** days.
- Sample standard deviation (divide by n−1). σ is floored at HRV 1 ms, RHR 0.5 bpm, sleep 0.15 h, steps 500.
- `z = (x − μ) / σ`. The observation is not part of μ or σ.
- HRV and sleep alert on a large negative z. Resting HR alerts on a large positive z. The other direction stays “in range”.
- `|z| ≥ 2` is warn, `|z| ≥ 3` is high (both settings are editable).
- Steps downward are informational from 2σ until **z ≤ −2.5** (warn), then high at zHigh.
- Sleep and steps ignore the current unfinished day. HRV and resting HR can update today.
- One alert per metric per day; a stronger severity clears an acknowledgement. Notifications fire only for a new warn/high or a severity upgrade, and only when the Settings toggle is on.
- CUSUM (`k = 0.5`, `h = 4` on the bad direction) is in Core and off unless `AppSettings.cusumEnabled` is set. The Settings screen does not expose it yet.

## Known limits of this scaffold

- Background HealthKit delivery is a stub (`HealthKitReader.enableBackgroundUpdates`). No observer query yet.
- Quantity days store `sampleCount = 1` because `HKStatistics` does not return a raw count. Sleep uses the asleep-sample count.
- Sleep is duration of asleep stages only (in-bed time is ignored), attributed to the wake day.
- Changing the window rebuilds from stored days. It does not re-download HealthKit history until the next Health refresh.
- The Watch status screen shows the last snapshot it received. Refresh asks the reachable iPhone app for a newer one.
- Example pattern replaces stored days. It is labeled on screen.

## Regenerating the Xcode project

`BaselineRing.xcodeproj` is meant to be opened as-is. `project.yml` describes the same targets for XcodeGen. Running `xcodegen generate` can put the Watch app in the legacy `Watch/` embed directory, which current Xcode rejects. Prefer the committed project. If you do regenerate, embed the Watch app and the intents extension in PlugIns (`dstSubfolderSpec = 13`), and embed the widget inside the Watch app the same way.
