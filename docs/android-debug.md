# Android debug APK

Debug APKs are produced only by GitHub Actions, never by a local Godot export unless the user explicitly asks for a local build.

## Trigger

Workflow: [`.github/workflows/android-debug.yml`](../.github/workflows/android-debug.yml).

It runs on `pull_request` (`opened` / `synchronize` / `reopened`) into the long-lived **`android-debug`** branch (same-repo heads only). A push to that branch alone does not build.

The job exports preset `Android Debug` via [`.github/scripts/export_android_debug.sh`](../.github/scripts/export_android_debug.sh) (CI-only: requires `ANDROID_EXPORT_CI=1`). Package `com.waigore.footballsim.debug`, arm64 only, signed with the committed debug key [`export/android/debug.keystore`](../export/android/debug.keystore) (`androiddebugkey` / `android`) and [`export_presets.cfg`](../export_presets.cfg).

## Publish

On success the workflow creates or updates a **prerelease** tagged `android-debug/<YYYY-MM-DD>/<sha>` (UTC date), titled `android-debug <YYYY-MM-DD> <12-char-sha>`, with asset `footballsim-<12-char-sha>-debug.apk`.

Install over a previous build: `adb install -r --no-incremental <apk>`. An incremental install on a full emulator fails without a non-zero exit, and the next launch then runs the previous APK — require `Success` in the output.

## Agent procedure

1. Prefer current `main` as the APK contents. Open a same-repo PR **into** `android-debug`.
2. If `main` → `android-debug` conflicts, branch from `origin/android-debug` (`chore/android-debug-sync`), merge `origin/main`, resolve conflicts **in favor of `main`**, push, and open (or retarget) the PR from that branch. Never force-push `android-debug`.
3. Wait for the **Android debug** check to succeed. Report the release URL and the `.apk` download URL. Do not stop at the PR URL alone.
4. Leave auto-merge alone unless the user asks; merging updates `android-debug` for the next sync.
5. Give that PR its **own head branch**. Auto-merge lands the first PR it finds for a commit with `--delete-branch`, and the deleted branch closes any PR sharing it.

## Device parity

A 105x68 m pitch needs the long edge, and the desktop overlay's 10-unit type is a one-millimetre hairline on a 420 dpi panel. `project.godot` pins sensor landscape, `stretch/aspect = expand` (the 20:9 width is used, not letterboxed) and ETC2/ASTC import, which an Android export requires.

`HudLayout` owns the phone layout. `overlay_scale()` maps one design unit to about one density point (`900 / screen height in dp`, clamped 1–2.6); `main.gd` scales the overlay layer by it and every rect is then derived from the smaller design viewport. `is_compact()` switches to phone metrics: scoreboard beside a three-or-five-row stats card, a seven-door control bar (teams joins it), the horizontal player card, and no 20-unit row to tap. Tap targets stay ≥ 44 design units — `tests/test_hud_layout.gd` asserts it, with the card and the pitch band.

Point events arrive in logical viewport units, so convert with `main.gd::_design(p)` before `hud.button_at()` or `selector.button_at()`. A tap picks a player from the tap point (`_pick`), never from a hover a finger never made.

## Local playtest

`tools/android_playtest.sh [seconds]` exports, installs, launches and prints the engine log. On a desktop build `-- --ui-scale=2.19` forces the phone overlay in a 2400x1080 window, so screenshots need no device.

## Device parity

A 105x68 m pitch needs the long edge, and the desktop overlay's 10-unit type is a one-millimetre hairline on a 420 dpi panel. `project.godot` pins sensor landscape, `stretch/aspect = expand` (the 20:9 width is used instead of letterboxed), and ETC2/ASTC import, which an Android export requires.

`HudLayout` owns the phone layout. `overlay_scale()` maps one design unit to about one density point (`900 / screen height in dp`, clamped 1–2.6); `main.gd` scales the overlay layer by it and every rect is then derived from the smaller design viewport. `is_compact()` switches to phone metrics: scoreboard beside a three-or-five-row stats card, a seven-door control bar (teams joins it), the horizontal player card, and no 20-unit row to tap. Tap targets stay ≥ 44 design units — `tests/test_hud_layout.gd` asserts it, with the card and the pitch band.

Point events arrive in logical viewport units, so convert with `main.gd::_design(p)` before `hud.button_at()` or `selector.button_at()`. A tap picks a player from the tap point (`_pick`), never from a hover a finger never made.

## Local playtest

`tools/android_playtest.sh [seconds]` exports, installs, launches and prints the engine log. On a desktop build, `-- --ui-scale=2.19` forces the phone overlay in a 2400x1080 window, so phone screenshots and geometry need no device.

## Out of scope

- Local JDK / Android SDK / Godot template install for this path
- Release (non-debug) signing or Play Store uploads
- Editing the workflow or keystore unless the user asked to change the pipeline
