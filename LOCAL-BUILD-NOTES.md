# Local build notes (eqMac v1.9.2)

Notes for this fork of [eqMac v1.9.2](https://github.com/bitgapp/eqMac/releases/tag/v1.9.2). They cover how to build it, what was changed and why, and the problems found along the way. Last verified 2026-10-12 with Xcode 27.0, CocoaPods 1.17.0, Node 24 and an Apple Silicon Mac with System Integrity Protection on.

## Building

```sh
./build.sh                    # UI + app + driver, Release, ad-hoc signed
./build.sh --skip-ui          # reuse native/app/Embedded/ui.zip
./build.sh --install-driver   # also install the driver (asks for your password)
```

Output goes to `build/Build/Products/Release/` (`eqMac.app` and `eqMac.driver`), and logs go to `build/logs/`.

Requirements: full Xcode in `/Applications` (the script uses it even if `xcode-select` points at the Command Line Tools), CocoaPods, Node and Yarn.

> **Don't build only from Xcode.** The Xcode project doesn't put `ui.zip` into the app; upstream adds it in their own release process. An app built without it crashes at launch in `UI.unarchiveZip`. `build.sh` copies it in and re-signs the app. If you do build in Xcode, copy `native/app/Embedded/ui.zip` to `eqMac.app/Contents/Resources/Embedded/` afterwards and run `codesign --force --deep -s - eqMac.app`.

What `build.sh` does:

1. Builds the Angular UI (`ui/`) and zips it into `native/app/Embedded/ui.zip`. It needs `NODE_OPTIONS=--openssl-legacy-provider` because Angular 12's webpack doesn't run on Node 17+ without it.
2. Runs `pod install`, but only when `Pods/Manifest.lock` differs from `Podfile.lock`.
3. Builds the `eqMac` and `Driver - Release` schemes with:
   - `MACOSX_DEPLOYMENT_TARGET=12.0`. Xcode 27 rejects the project's 10.12/10.13 targets.
   - `CODE_SIGN_IDENTITY=-` and no team, i.e. ad-hoc signing.
   - `EQMAC_SKIP_DRIVER_INSTALL=YES`, which skips the driver project's own `sudo` install step. That step fails in an unattended build.
4. Copies `ui.zip` into the app and ad-hoc signs both bundles.

## Installing the driver

```sh
./build.sh --skip-ui --install-driver
```

Or by hand:

```sh
# back up an existing driver first
sudo cp -R /Library/Audio/Plug-Ins/HAL/eqMac.driver ~/eqMac-driver.bak
sudo rm -rf /Library/Audio/Plug-Ins/HAL/eqMac.driver
sudo cp -R build/Build/Products/Release/eqMac.driver /Library/Audio/Plug-Ins/HAL/
sudo killall coreaudiod
```

- **Version range:** the 1.9.2 app only accepts driver versions from 1.3 up to, but not including, 2.0 (`Driver.swift`). The driver built here is 1.3.1. A driver from a newer eqMac release (for example 2.6.0) is reported as "incompatible". Reinstalling that release brings its driver back.
- **Restarting the audio system:** use `killall coreaudiod`. The driver project's own script uses `launchctl kickstart -k system/com.apple.audio.coreaudiod`, which fails with "Operation not permitted while System Integrity Protection is engaged". After `killall`, launchd restarts `coreaudiod` on its own.
- **Signing:** the driver must be signed, and ad hoc is enough. macOS silently refuses to load unsigned arm64 code. The plugin then shows up without its audio device, and the app reports the driver as missing or incompatible.

## Changes from upstream

### Build fixes

| Problem | Fix | Where |
|---|---|---|
| `bitgapp/AMCoreAudio` was deleted from GitHub, and the pinned commit `b312d15` is only fetchable by SHA from the original repo, which CocoaPods' plain clone can't do | That commit is vendored and used via `:path` | `native/Podfile`, `native/vendor/AMCoreAudio` |
| The `AudioKit/Specs` pod source was deleted, and no pod uses it | Commented out | `native/Podfile` |
| Newer macOS SDKs no longer have the `CoreAudio.AudioHardwareBase` submodule | Changed to `import CoreAudio` | `native/vendor/AMCoreAudio/Source/**` |
| Sentry 7.1.3 relied on headers being included indirectly, which newer libc++ and the SDK no longer do | A `post_install` hook adds `#include <exception>` and `#include <sys/_types/_ucontext64.h>` | `native/Podfile` |
| Xcode 27 couldn't resolve the `Minizip` module that `Zip`'s Swift module depends on | Added the Minizip module path to the app's `SWIFT_INCLUDE_PATHS`, and `$(inherited)` to the app target's setting | `native/Podfile`, `app/eqMac.xcodeproj` |
| A post-build step uploaded debug symbols to upstream's Sentry project, and failed without `sentry-cli` | Disabled (`exit 0`) | `app/eqMac.xcodeproj` (Run Script phase) |
| The driver's post-build step installs it with `sudo` | Skipped when `EQMAC_SKIP_DRIVER_INSTALL=YES` | `driver/Driver.xcodeproj` (Run Script phase) |
| The UI build failed: TypeScript auto-loaded every `@types` package, and newer `@types/minimatch`/`glob` don't work with TypeScript 4.3 | Limited the auto-loaded types to `node` and `google.analytics`, added `skipLibCheck`, and pinned `@types/minimatch@5.1.2` | `ui/tsconfig.json`, `package.json` |
| Upstream git-ignores `yarn.lock`, so fresh clones resolve whatever versions are newest | Root `yarn.lock` committed (`!/yarn.lock` in `.gitignore`) | `.gitignore`, `yarn.lock` |
| `ui/package.json`'s build copies into `native/app/Embedded/`, which doesn't exist in a fresh clone | `build.sh` creates it | `build.sh` |

`native/vendor/AMCoreAudio` is commit `b312d1509ef863dea3ca56cfa3f57451de4ff721` of [rnine/AMCoreAudio](https://github.com/rnine/AMCoreAudio) (MIT), plus the import change above. It's committed as plain files, not as a submodule.

The root `yarn.lock` is committed, although upstream git-ignores it, so that fresh clones build with the exact package versions that are known to work. `build.sh` installs with `--frozen-lockfile`.

### Behavior changes

- **Feature guards disabled.** The volume, balance, equalizer and output sections are always shown. They can't be turned off in Settings (`ui/src/app/services/ui.service.ts`).
- **The app always uses its bundled UI.** Release builds used to load the UI from `https://ui-v3.eqmac.app`, or from a cached remote copy, so local UI changes never appeared. The app now always unpacks `ui.zip` from its own bundle (`native/app/Source/UI/UI.swift`).
- **Update checks removed.**
  - Sparkle is never initialized, and the app starts straight away instead of waiting for an update check (`AppDelegate.swift`).
  - The UI's "check for updates" action does nothing (`Application.swift`).
  - `SUFeedURL` was removed and `SUEnableAutomaticChecks` set to false (`Info.plist`).

### Bug fixes

- **Driver crashed the audio helper (memory tagging).** `UInt32.init(from: [UInt8])` let a pointer escape `withUnsafeBufferPointer` and read freed memory. On newer Apple Silicon Macs, memory tagging (MTE) catches this and kills `com.apple.audio.Core-Audio-Driver-Service.helper` (`EXC_ARM_MTE_TAGCHECK_FAIL`) the first time CoreAudio queries the driver. The plugin loaded but never published its device. Replaced with a safe byte fold that produces the same values (`native/shared/Source/NumericTypesConversions.swift`).
- **Crash on quit.** `getLastKnowDeviceFromStack()` force-unwrapped `Driver.device`, which crashed whenever the app quit without a driver device. `stopSave` now skips switching back when there's no device (`Application.swift`).

## Parametric EQ and AutoEq

A third equalizer type, **Parametric**, with AutoEq headphone presets.

- **Native code** (`native/app/Source/Audio/Effects/Equalizers/Parametric/`):
  - `ParametricEqualizer.swift`: the EQ, up to 20 bands on one `AVAudioUnitEQ`.
  - `ParametricEqualizerPreset.swift`: the preset model, plus the `ParametricEQ.txt` (Equalizer APO) parser.
  - `ParametricEqualizerState.swift`: saved state.
  - `ParametricEqualizerDataBus.swift`: the routes under `/effects/equalizers/parametric`.
  - `AutoEq.swift`: the AutoEq client.
- **UI** (`ui/src/app/sections/effects/equalizers/parametric-equalizer/`):
  - The panel, with a response graph, preamp and band table.
  - `parametric-equalizer.response.ts`: the response math.
  - `autoeq-dialog/`: the AutoEq picker.

### Filter accuracy: the Q → bandwidth conversion

AutoEq designs filters with Q values (RBJ Audio EQ Cookbook biquads), but `AVAudioUnitEQ` takes bandwidth in octaves. I compared the two by rendering sine waves offline through `AVAudioUnitEQ`:

- **Naive conversion** (`2·asinh(1/2Q)/ln 2`): off by up to **1.35 dB** in the treble at 44.1/48 kHz. That's exactly where headphone corrections matter.
- **With bilinear frequency warping** (multiply by `sin(w0)/w0`, where `w0 = 2π·f/fs`): within **0.01 dB** of the RBJ response for peaks and shelves at 44.1, 48 and 96 kHz.
- **Shelf types:** shelves must use `.resonantLowShelf` / `.resonantHighShelf` with that bandwidth. Plain `.lowShelf`/`.highShelf` only match at Q ≈ 0.707.

So the conversion depends on the sample rate: `Engine` passes the device's rate to the equalizer through `Equalizer.sampleRate`. The UI's response graph uses the same RBJ formulas, and its values were checked against the measurements.

### Data

- **Sources:**
  - `results/INDEX.md`: about 8,850 results from 23 measurement sources.
  - `dbtools/manufacturers.tsv`: about 730 brands with aliases.
  - Both come from `raw.githubusercontent.com/jaakkopasanen/AutoEq/master`.
- **Caching:** files are cached in `~/Library/Application Support/com.bitgapp.eqmac/AutoEq/` for 7 days. When a download fails, the app uses the stale cache. Settings (cog) → "Update AutoEq Database" forces a refresh.
- **Brand/model split:** a port of AutoEq's `ManufacturerIndex.find`, which matches the longest leading run of words against brand aliases. It matched all 8,850 entries, to 659 brands.
- **Source order:** measurements are sorted with oratory1990, crinacle, Rtings and Innerfidelity first.
- **Downloading a preset:** `results/<path>/<name> ParametricEQ.txt`. This was tested against one result from each of the 23 sources, and against names containing `& + ' ( ,`.
- **Search:** every query word must appear in "brand model". Spaces and punctuation are ignored, so `hd650` finds "HD 650" and `athm50x` finds "ATH-M50x".
- **License:** AutoEq is MIT-licensed (Jaakko Pasanen), and the dialog credits it.

### Presets and state

- **Storage:** presets are saved in UserDefaults under `parametricEqualizerPresets`.
- **Editing:** like the Advanced EQ, editing any preset writes into "Manual".
- **AutoEq presets** are named `<Headphone> · <source>`. Loading the same one again updates it instead of adding a duplicate.
- **Import / export:**
  - Import accepts eqMac JSON exports or `ParametricEQ.txt` files.
  - Export writes JSON.
- **Saved state:** the new `parametric` state uses `@DefaultCodable`. `ApplicationState.load()` decodes strictly and silently falls back to default settings for *everything* if any field fails. A plain new field would have reset every user's settings.

### UI: no floating dropdowns in dialogs

`eqm-dropdown` opens its list inside the web view, so it gets cut off when the app window is short. The AutoEq dialog therefore uses a search box and fixed-height scrollable lists instead.

`app.component.ts` also now counts open dialogs (`.cdk-overlay-pane`) in the window's minimum height, and re-syncs when a dialog opens or closes. The window grows to fit a dialog, then shrinks back.

## Known limitations

- **Filter types:** only peak (`PK`) and low/high shelf (`LSC`/`HSC`) filters. That covers all of AutoEq's output. Files with LP/HP or other types are rejected with a message.
- **Main preset list:** the preset list in the main window is still an `eqm-dropdown`. It opens towards whichever side has more room and scrolls, but it hasn't been tested with a very large number of presets.
- **Signing:** the app and driver are ad-hoc signed only. They run on this Mac, but not on other Macs without being re-signed.
- **No automated tests:** the project has no test target. The checks above were run as standalone harnesses (offline `AVAudioUnitEQ` rendering, the AutoEq client against live data, and the response math) plus headless screenshots of the UI with a mocked native bridge. They aren't part of the repo.
- **Inherited from upstream:** the driver project hard-codes `~/askpass.sh` for `sudo -A`. `build.sh` skips that step.

## Debugging tips

- **Blank window or "driver incompatible":** check whether CoreAudio actually has the device. `system_profiler SPAudioDataType` should list eqMac. Also look in `/Library/Logs/DiagnosticReports/` for `Core-Audio-Driver-Service.helper` crashes. The driver runs inside that helper process, not inside `coreaudiod`.
- **App crash reports:** they're in `~/Library/Logs/DiagnosticReports/eqMac-*.ips`.
- **Previewing the UI without the app:** serve the unzipped `ui.zip` and define `window.WebViewJavascriptBridge` with a `callHandler(handler, data, cb)` that answers `"<METHOD> <route>"` requests. That's enough to render any screen in a browser.
