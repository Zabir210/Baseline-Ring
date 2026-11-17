# First-build checklist

Baseline Ring has never been compiled. This is the order to get it running on a Mac, then on an iPhone and Apple
Watch, and to check each part that is still unverified. Every setting below comes from the committed project
files (`BaselineRing.xcodeproj`, the `.entitlements` and `Info.plist` files, and the source).

Tick the boxes as you go. When something fails, the error and its fix are usually in **Common errors** at the end.

---

## 0. Before you start

- [ ] **Xcode 16 or newer.** The project file uses format 77 and synchronized folders, which older Xcode can't open.
- [ ] **iPhone on iOS 17+ and Watch on watchOS 10+.** These are the deployment targets for every target. They can't go lower because of SwiftData.
- [ ] **Apple Developer account.** A free personal team is enough for the simulator. Running HealthKit on a real iPhone needs the paid Developer Program.
- [ ] **Developer Mode on** for the iPhone and the Watch (Settings → Privacy & Security → Developer Mode). Xcode asks for it the first time you run on a device.

## 1. Get the code and pick the branch

Build the branch with the Nov 12 compile fix, not `main`. It is `main` plus one commit that rewrites a few Swift
expressions in the score code so they type-check reliably. It changes no behavior.

```bash
git clone https://github.com/Zabir210/Baseline-Ring.git
cd Baseline-Ring
git checkout claude/stoic-turing-sx8icb
open BaselineRing.xcodeproj
```

- [ ] Open **`BaselineRing.xcodeproj`**. Do **not** run `xcodegen generate`: it can put the Watch app in the old `Watch/` folder, which current Xcode rejects.
- [ ] Wait for Xcode to finish resolving the local `BaselineCore` package (no internet dependencies).
- [ ] If it builds, merge the fix into `main` later so `main` builds too.

## 2. Prove the math compiles first (no signing needed)

The score and baseline code lives in the `BaselineCore` Swift package and has no UI. Test it alone before fighting
signing:

```bash
cd BaselineCore
swift test
```

- [ ] All tests pass. They check the z-score engine by hand-calculated numbers (sample σ, the floors on σ, which direction alerts for each metric, the step bands, the example series).

If this fails, the problem is in the Swift code, not in signing or devices. Fix it here first.

## 3. Run in the simulator

- [ ] Scheme **BaselineRing**, destination any **iPhone simulator**, press Run.
- [ ] If Xcode asks for a team: each target → **Signing & Capabilities** → Team → your personal team. Signing is already set to Automatic for every target.
- [ ] Simulator Health data is usually empty, so open **Settings → Load example pattern**. Today should show the cards and a banner saying the numbers are not your health data.
- [ ] Run tests: scheme **BaselineRing** → **Product → Test** (runs `BaselineRingTests`, which compiles the package tests inside the app).

## 4. Signing for real devices

There are four targets, one App Group, and HealthKit on the iPhone app only:

| Target | Bundle ID | Capabilities |
|---|---|---|
| BaselineRing (iPhone app) | `com.zabir.baselinering` | HealthKit, App Groups |
| BaselineRingWatch (Watch app) | `com.zabir.baselinering.watchkitapp` | App Groups |
| BaselineRingWidgets (complication) | `com.zabir.baselinering.watchkitapp.widgets` | App Groups |
| BaselineRingIntents (Shortcut) | `com.zabir.baselinering.intents` | App Groups |

App Group in every entitlements file: `group.com.zabir.baselinering`

- [ ] For **all four** targets: Signing & Capabilities → Team → your paid team.
- [ ] iPhone target: confirm **HealthKit** and **App Groups** show in the capabilities list. Leave "Clinical Health Records" and "Background Delivery" off.
- [ ] Watch, widget and intents targets: confirm **App Groups** shows, with the same group id ticked.
- [ ] If the group shows red, click the refresh button next to it, or add `group.com.zabir.baselinering` in the developer portal (Certificates, Identifiers & Profiles → Identifiers → App Groups) and tick it on all four App IDs.
- [ ] The bundle IDs must be unique in Apple's system. If Xcode says one is taken, change the prefix on **all** targets together (for example `com.zabirislam.baselinering…`), and change `WKCompanionAppBundleIdentifier` in `BaselineRingWatch/Info.plist` to the new iPhone bundle ID. The Watch app won't install if those two don't match.

## 5. Run on your iPhone and Watch

- [ ] Plug in the iPhone, pick it as the destination for scheme **BaselineRing**, press Run. This builds the Watch app, the complication and the Shortcut extension with it.
- [ ] On first launch, if iOS says the developer isn't trusted: Settings → General → VPN & Device Management → trust your profile.
- [ ] To put it on the Watch: run scheme **BaselineRingWatch** with the paired Watch as the destination, or install it from the Watch app on the iPhone (My Watch → Available Apps).

## 6. Test each unverified part

### Health data path

- [ ] Tap **Allow Health Access** and approve all categories. The app only asks to *read*; there should be no write switches.
- [ ] Today shows the Readiness and Sleep score cards, then one card per metric (HRV, resting heart rate, sleep, steps) with value, baseline mean, z-score and status. Pull to refresh.
- [ ] Each metric says **Learning** until it has 10 days of data; with your existing Watch history it should leave Learning right away.
- [ ] Spot-check one number against the Health app (for example last night's sleep or yesterday's steps). Sleep counts only asleep time and belongs to the day you woke up.
- [ ] Tap the Readiness card and confirm it lists which metrics moved the score and by how many standard deviations. Tap a metric card and confirm its sparkline.

### Database (the new `DayTag` journal model)

- [ ] Open **Settings → Storage**. It should show no warning.
  - "App Group … is not active" → the App Groups capability is missing on the iPhone target (step 4).
  - "Couldn't open the saved store. This launch is temporary" → the saved store couldn't open, most likely because the new journal model changed the schema. Delete the app from the phone and run again.
- [ ] Open **Journal and tag effects** on Today, add a tag (alcohol, late meal, travel, stress, illness or custom), quit the app fully, reopen it, and check the tag is still there. If it's gone, the app is running on the temporary store.

### Watch app and complication

- [ ] Open the Watch app and tap **Refresh** with the iPhone app open nearby. The status list should match the iPhone. The iPhone pushes its snapshot to the Watch; they don't share a folder.
- [ ] Add the complication to a watch face (long-press the face → Edit → Complications → Baseline). It shows the readiness number, or "–" when there isn't enough data.

### Shortcut

- [ ] Open the Shortcuts app and search for **Am I Off Baseline?**. Run it. It should answer in text without opening the app, including the readiness line.

### Not built yet (don't test)

- Background updates: `enableBackgroundUpdates()` is an empty stub, so data refreshes only when you open the app.
- Notifications: the Settings toggle exists, but nothing is delivered in the background yet.

## Common errors

| Error | Fix |
|---|---|
| "The project … cannot be opened because it is in a future Xcode project file format" | Update to Xcode 16 or newer. |
| "The compiler is unable to type-check this expression in reasonable time", or key-path errors in `Scores/` files | You're on `main`. Switch to `claude/stoic-turing-sx8icb` (step 1). |
| "Signing for … requires a development team" | Pick a team on every target, not just the iPhone app. |
| "Provisioning profile doesn't include the HealthKit entitlement" or the App Group | Turn the capability on in Signing & Capabilities, or in the developer portal for that App ID, then let Xcode regenerate the profile. A free personal team can't sign HealthKit for a device. |
| "Failed to register bundle identifier" / "not available" | Change the bundle ID prefix on all four targets and `WKCompanionAppBundleIdentifier` (step 4). |
| Watch app doesn't appear on the Watch | `WKCompanionAppBundleIdentifier` doesn't match the iPhone bundle ID, or the Watch is below watchOS 10. |
| Today shows no data on a real phone | Health access was denied: Settings → Health → Data Access & Devices → Baseline Ring → turn categories on. |
| Watch says nothing received | Open the iPhone app first, keep both devices near each other, then tap Refresh on the Watch. |
| Build fails after running `xcodegen generate` | Discard the changes to `BaselineRing.xcodeproj` (`git checkout BaselineRing.xcodeproj`) and use the committed project. |
