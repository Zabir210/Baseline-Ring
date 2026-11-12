# Oura-style parity

Oura-style insights from the Apple Watch you already own. No ring. No subscription. The number on screen is a weighted personal z-score, and the detail screen lists every term in standard deviations and points.

The z-score engine in `BaselineCore` is unchanged in its rules (21-day window, 10-day minimum, epsilon floors, direction). Scores sit on top of it.

## Feature map

| Oura-style idea | What shipped | Where |
|---|---|---|
| Readiness 0–100 | Neutral 80. Weights: HRV 0.40, resting HR 0.30, sleep duration 0.20, prior-day activity load 0.10. Each term is capped at ±3σ. HRV down, resting HR up, short sleep, and a high load subtract points. | `ReadinessScoreCalculator` |
| Confidence | Low withholds the number. Needs two fresh core signals (today or yesterday) with at least 10 baseline days. High only when HRV, resting HR, and sleep are all included and each has 21+ days. Sparse HRV is left out and named. | same |
| Sleep score | Stage path when this night has core+deep+REM and 7 earlier staged nights exist: duration 0.40, deep 0.25, REM 0.25, efficiency 0.10. Otherwise duration 0.50, in-bed efficiency 0.30, bedtime/wake consistency 0.20. | `SleepScoreCalculator` |
| Activity / strain | Daily load from steps (0.45), active energy (0.35), and estimated workout HR minutes (0.20). A day that matches the reference caps (10k steps, 500 kcal, 30 min) is about 67. Yesterday’s load z feeds readiness. | `ActivityLoadCalculator`, `HealthKitReader` |
| “Possibly getting sick” | Two or more latest days with HRV z ≤ −1 and resting HR z ≥ +1. Optional wrist-temperature z ≥ +1 is mentioned when those samples exist. It cannot raise the flag alone. UI text is “Your pattern changed”. | `PatternChangeDetector` |
| Tags | Alcohol, late meal, travel, stress, illness, custom. Stored in SwiftData. Next-day HRV (ms) and readiness versus untagged days, after 5 tagged nights. | `DayTag`, `TagEffectCalculator`, Journal screen |
| Today / Watch / complication / Shortcut | Readiness and sleep cards with tap-through. Watch and complication show the readiness number or “–”. “Am I off baseline?” appends the readiness line. | app, watch, widget, intents |

## Formulas worth keeping stable

Readiness points for one included metric: `weight × 50 × clamp(directionalZ, −3, 3) / 3`.

Directional z is the raw z for HRV and sleep, the negated z for resting HR and activity load.

Sleep and readiness both start at 80 and clamp to 0…100. A missing term contributes 0 and the sentence says it was left out. Weights are not quietly renormalized.

Activity component: `min(2, value / denominator)`. Denominator is the personal baseline when it is above the floor, otherwise 10_000 steps, 500 kcal, or 30 minutes. `load = 100 × weighted sum / 1.5`.

Workout minutes are an estimate: average heart rate during the workout ≥ 120 bpm counts the full duration, 100–119 bpm counts half. This is not a five-zone model and it does not use age.

## Hardware

See the table in `README.md`. Short version: the app targets iOS 17 and watchOS 10 because SwiftData cannot go lower, and watchOS 10 is the newest system Series 4 can run. iOS 16 and watchOS 8 are not build targets. Stage APIs and wrist temperature are wrapped in `#available(iOS 16, *)` so a later drop of the deployment target has an obvious gate. On today’s target those branches are always taken; missing data is what selects the fallback.

## Still needs work

- Not compiled on this branch. There is no Xcode on the machine that wrote it. Treat HealthKit queries, the widget, and SwiftData migration (new `DayTag` model) as unverified until a Mac build.
- Background delivery is still the empty `enableBackgroundUpdates()` stub.
- Activity baselines are not stored. The load number uses reference caps unless a caller passes a baseline. Readiness uses the z-score of the recent load series, which is comparable only when the same inputs exist each day.
- Tag effects after a cold launch use stored daily rows (steps stand in for activity). Energy, zone minutes, and wrist temperature are on the last Health fetch held in memory, not in SwiftData.
- Adding `DayTag` to the schema can fail an existing store open. The app already falls back to an in-memory store and says so. Confirm that on a phone that already ran the weekend build.
- The illness journal tag is a label the user applies. The app does not decide that someone is ill.
