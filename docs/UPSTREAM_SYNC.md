# Upstream synchronization

## Current baseline

- Last deployed code: `cae13c59` (targeted fixes plus encoder-safe native resolution).
- Reconciliation branch: `integrate/upstream-2026-10-31`.
- Upstream target: `fa428059` on `upstream/Integration`.
- Code reconciliation merge: `078be62a` (parents `c8507e85` and `fa428059`).
- Reviewed candidate code: `ccdf909c` (compatibility follow-up to the merge).
- Status: integration candidate; not approved for promotion to `main` until the
  checks below, including physical-device acceptance, are recorded.

The earlier selective ports did not record upstream ancestry. This candidate
uses a real merge to establish it. Before promotion, `main` still has the old
merge base; after promotion, later merges only need to reconcile newer commits.

### Recorded candidate verification (2026-10-31)

- Debug Duo simulator build: passed.
- Debug generic iPhone build, unsigned: passed.
- Final v1.3 migration checks from v1.0, v1.1 and v1.2, with legacy pinch enabled
  and disabled: all six passed. Explicit disabled gesture selections survive.
- Existing Duo fold/Settings/resolution smoke: passed (22 non-echo steps).
  Host discovery produced a small-motion idle warning; destination and resolution
  checks passed. No stream was started by this test.
- `git merge-base --is-ancestor fa428059 078be62a`: passed. This is a real merge,
  not an ancestry-only placeholder.
- Pending: physical XR/video, rotated trackpad, saved-widget profiles, microphone
  and live audio lifecycle acceptance. tvOS/macOS runtime acceptance is untested.

Review found and resolved two additional compatibility gaps: View Zoom is disabled with
Metal (its video view does not participate in the scroll transform), and legacy
pinch preferences are retained using an unset sentinel rather than treating every
old store as an explicit pinch-disabled selection. Both final builds, migration
checks and the smoke replay passed after these fixes; the bounded review recheck
reported no remaining concrete issue in those areas.

The installed Duo code is `cae13c59`; do not install/promote the candidate
as a verified replacement until those acceptance gaps are addressed.

### Native-resolution hotfix acceptance (2026-10-31)

On the deployed targeted-fix build, 1080p started successfully but FullScr/Window
failed with the same H.264/HDR-off settings. The capture showed successful
handshake/audio followed by `-100` (no video traffic), with native size 2669×1878.
`cae13c59` aligns only measured native presets to even pixels (2668×1878 here),
leaves custom dimensions unchanged, and preserves the actual error in the dialog
instead of claiming an external probe proves the local network is blocked.
The user confirmed native H.264/HDR-off streaming works after the in-place update.
Ten standalone alignment cases pass. Other codecs, HDR and the complete
reconciliation candidate are **not** covered by this confirmation.

## Branch and merge policy

- `upstream/Integration` is reconciled into `integrate/upstream-YYYY-MM-DD`, starting from `origin/main`. Review and test there; only then promote to `main`.
- Make a real `--no-ff` merge. Do not squash/rebase an upstream integration, or use
  `git merge -s ours` to pretend code has been integrated. A selective cherry-pick
  may be appropriate for an urgent fix, but it is not a replacement for this merge.
- Enable local reuse carefully: `git config rerere.enabled true` and `git config rerere.autoupdate false`. Review every rerere-resolved diff before staging it.
- Sync nested dependencies with `git submodule sync --recursive` and `git submodule update --init --recursive`; retain the pinned submodule refs.
- Preserve signing identity: bundle `com.billyjacoby.voidlink`, team `93BYVNPTHR`.

### One-time setup on each development machine

```sh
git remote -v
# Add only if the upstream remote is absent:
# git remote add upstream https://github.com/The-Fried-Fish/VoidLink-previously-moonlight-zwm.git
git config --local rerere.enabled true
git config --local rerere.autoupdate false
```

`rerere` remembers conflict resolutions in this clone, not in GitHub. New clones
must enable it again and do not inherit this clone's resolution cache. Reused
text can still be semantically wrong, so inspect it before `git add`.

### Each subsequent update

Start with a clean worktree. Commit or deliberately preserve outstanding work;
never reset or discard unrelated changes to make a merge easier.

```sh
git fetch origin
git fetch upstream
git switch main
git merge --ff-only origin/main
git switch -c integrate/upstream-YYYY-MM-DD
git log --oneline HEAD..upstream/Integration
git merge --no-ff --no-commit upstream/Integration
```

Resolve conflicts by behavior, not by selecting an entire side. Also inspect
automatically merged files: selective ports can produce duplicate declarations
without a textual conflict. Update dependencies only after checking that their
worktrees have no local changes:

```sh
git submodule foreach --recursive git status --short
git submodule sync --recursive
git submodule update --init --recursive
git diff --name-only --diff-filter=U
git diff --check
git diff --cached --check
```

Incoming upstream/vendor whitespace is not a reason to rewrite whole files.
Distinguish inherited warnings from new resolution errors; do not ignore conflict
markers or whitespace introduced by our resolutions.

Stage reviewed resolutions and finish the merge with a message naming the
upstream tip and the intentional fork differences. Push the candidate for review:

```sh
git add <reviewed-files>
git commit
git merge-base --is-ancestor fa428059 HEAD # use the fetched tip for future updates
git push -u origin integrate/upstream-YYYY-MM-DD
```

Only after verification and physical acceptance:

```sh
git switch main
git merge --ff-only origin/main
git merge --no-ff integrate/upstream-YYYY-MM-DD
git push origin main
```

Keep the merge commit and its parents. Never force-push shared `main`. If `main`
changed during validation, merge it into the candidate and repeat affected checks.

## Verification gates

Run these checks on the candidate branch. Use a simulator UDID from `xcrun simctl list devices available`, not an assumed
device name. These are build checks; the project has no app unit-test target:

```sh
xcodebuild -project VoidLink.xcodeproj -scheme VoidLink -configuration Debug \
  -destination 'platform=iOS Simulator,id=<simulator-udid>' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project VoidLink.xcodeproj -scheme VoidLink -configuration Debug \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
swift BuildScripts/check-settings-migration.swift /path/to/VoidLink.app/Limelight.momd 1.0
swift BuildScripts/check-settings-migration.swift /path/to/VoidLink.app/Limelight.momd 1.1
swift BuildScripts/check-settings-migration.swift /path/to/VoidLink.app/Limelight.momd 1.0 pinch-off
swift BuildScripts/check-settings-migration.swift /path/to/VoidLink.app/Limelight.momd 1.1 pinch-off
swift BuildScripts/check-settings-migration.swift /path/to/VoidLink.app/Limelight.momd 1.2
swiftc VoidLink/Utility/NativeStreamResolution.swift BuildScripts/check-native-resolution.swift -o /path/to/check-native-resolution
/path/to/check-native-resolution
```

If Xcode reports a missing Metal toolchain, install it with
`xcodebuild -downloadComponent MetalToolchain`. For stale precompiled-header errors,
retry with `GCC_PRECOMPILE_PREFIX_HEADER=NO` rather than deleting unrelated caches.
For repeat offline builds with resolved dependencies, `-skipPackageUpdates` and
`-disableAutomaticPackageResolution` can be appended.

Replay `.argent/flows/duo-upstream-fixes-smoke.yaml` with Argent's `flow-execute`
tool, specifying the repo as `project_root` and a dedicated Duo simulator as
`device`. Start on the closed cover panel. It changes the simulator's saved
resolution to 1080p and ends closed with Settings open; it does **not** start a
stream or test audio/XR. Exact resolution checks intentionally use AX waits
because the native runner tree exposes a different projection. Discovery activity
may cause an idle warning; successful destination checks are still required.

Migration checks create disposable databases, never modify installed app data,
and verify saved resolution, rotation preference, hosts, app relationships and
hidden state. Extend them whenever a new shipped model version is introduced.

The simulator flow is for logic and UI only. Do not infer physical-device behavior
from it. Physical acceptance is required before promotion for risky behavior.

Verify this invariant matrix:

| Area | Required coverage |
| --- | --- |
| XR | AVSampleBuffer and Metal; connect before/during stream, disconnect/reconnect, local video restoration |
| Trackpad | Portrait/landscape rotation, show/hide surface, rotate while dragging, mode switches; no stuck mouse buttons/native contacts |
| Orientation | Navigation rotates; local streaming locks only when Rotate While Streaming is off; external controls remain rotatable |
| Widgets | Editor save/reload/undo, portrait runtime menu, docked controls, folding/cancelled transitions; saved normalized geometry must not drift |
| Launch | Default app per host, hidden-default clearing, visible fallback, all-apps-hidden alert |
| Duo | Launch closed/open; fold with Settings and stream open; fixed/custom presets stay exact; native presets follow active display |
| Audio | Long playback, buffering limit, mic mute/PTT, interruptions, background/PiP, stop/restart; no stale playback recovery after teardown |

## Fork-specific conflict decisions

- Keep `OrientationHelper` and streaming-only rotation restrictions, including
  lookup through upstream's new root-controller wrapper. Do not reintroduce an
  app-wide landscape lock in `AppDelegate`.
- The stream controller owns iOS 27 scene-accessory registration. Do not also
  register another accessory on the root controller. Keep weak render ownership,
  renderer-specific view selection, local restoration and render-view
  `ScreenChanged` notifications after layout.
- Use `relativeTouchCoordinateView` for rotated external-trackpad coordinates.
  Upstream zoom, cursor-follow and keyboard panning must not resize the phone's
  trackpad surface while the video is externally routed.
- Portrait widget frames are presentation only. Keep stable profile-size and
  transition-start serialization helpers; never save docked slivers/menu frames
  as the user's layout or restore old folder state on a non-widget reload.
- Preserve host-UUID-keyed default Launch app preferences and hidden-app handling
  when adopting upstream host/app UI changes.
- Keep bounded audio admission and lifecycle-generation guards around queued
  resets, scheduling and teardown, even if upstream changes microphone handling.
- View Zoom/cursor-follow is available only for the standard renderer, not Metal
  or the external trackpad surface. Persisted unsupported selections must also be
  gated at runtime, not just hidden from the Settings picker.
- Native display/window sizes must use `NativeStreamResolution.alignedSize` in
  both Settings and launch configuration. Odd pixel dimensions can complete the
  handshake yet leave the host sending no video. Keep explicit custom sizes exact;
  an internet connectivity probe must not mask the actual termination reason.

Keep old Core Data versions immutable. Candidate version 1.3 inherits
`audioBufferLimitMs` and adds upstream's `floatingKeyboardButton`,
`zoomViewportPointerVelocityFactor`, `trackpadGestureMode`, and
`trackpadGestureSensitivity`; it retains deprecated `enablePinch`. The new gesture
mode defaults to -1 (unset): snapshots map the old pinch flag to Ctrl+scroll or
disabled until the user saves a new selection. Explicit disabled (0) is never
overwritten. Version 1.2 is retained for the intermediate simulator candidate;
deployed `main` remains on version 1.1 until promotion.

## Recovery and deployment

Before a merge commit exists, `git merge --abort` returns a clean, dedicated
candidate branch to its pre-merge state. Do not abort if someone has added
unrelated work without first preserving it. After committing, leave a failed
candidate unpromoted and fix it there; do not rewrite published history.

Build a signed device artifact only after the checks pass:

```sh
xcodebuild -project VoidLink.xcodeproj -scheme VoidLink -configuration Debug \
  -destination 'id=00008160-0000146C0CE80036' -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008160-0000146C0CE80036 /path/to/VoidLink.app
```

Installation must be an **in-place update**. Never uninstall to resolve a
migration/signing error: that would erase settings, paired hosts and saved state.
Physical launch requires the phone to be unlocked; Argent physical UI control
also requires USB. Record the tested commit, upstream tip, build results and
remaining acceptance gaps here before promotion. `main` stays on the tested
release until that decision is explicit.
