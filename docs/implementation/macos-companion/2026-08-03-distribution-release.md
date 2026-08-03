# AgentMeter macOS Distribution and Release Implementation Plan

**Goal:** Turn the tested SwiftUI app and Python bridge into a clean installable AgentMeter.app,
with a production icon, managed background helper, safe legacy migration, release verification,
and complete public documentation.

**Architecture:** Generate a deterministic native icon asset, package the Python bridge as a
self-contained one-folder helper inside a nested background app, assemble the Swift executable and
resources into the main app, and manage both through ServiceManagement. Keep unsigned developer
bundles reproducible; sign, harden, notarize, and archive only in an explicit release step.

**Tech stack:** SwiftPM release build, Asset Catalog Compiler, PyInstaller one-folder mode,
ServiceManagement, codesign, notarytool, stapler, GitHub Actions macOS, shell scripts with strict
error handling.

## Global constraints

- A clean supported Mac must not need Python, the repository, Xcode, or developer tools.
- Main bundle ID: `com.prabhavalabs.agentmeter`.
- Helper bundle ID: `com.prabhavalabs.agentmeter.bridge`.
- The helper is background-only and exposes no Dock icon or window.
- Main app launch-at-login and helper registration are user-controlled and reversible.
- Never run the legacy LaunchAgent and bundled helper together.
- Preserve existing configuration and bounded history during migration.
- Release signing credentials stay in the keychain/CI secrets and never enter files or logs.
- Production app and helper use Hardened Runtime and accurate privacy descriptions.
- Firmware updating remains outside the application.
- Release documentation lists Nipun Theekshana as the sole author and contains no automated
  co-author attribution.

## File map

| File | Responsibility |
| --- | --- |
| `desktop/Artwork/generate_app_icon.swift` | Deterministic icon drawing source |
| `desktop/Sources/AgentMeterUI/Resources/Assets.xcassets/AppIcon.appiconset` | Required icon PNGs |
| `packaging/AgentMeter-Info.plist` | Main app metadata and privacy copy |
| `packaging/AgentMeter.entitlements` | Main app hardened-runtime entitlements |
| `packaging/AgentMeterBridge-Info.plist` | Background helper metadata/Bluetooth privacy copy |
| `packaging/AgentMeterBridge.entitlements` | Helper entitlements |
| `packaging/AgentMeterBridge.spec` | Reproducible PyInstaller one-folder configuration |
| `desktop/scripts/build-app.sh` | Unsigned deterministic app assembly |
| `desktop/scripts/sign-release.sh` | Nested signing and verification |
| `desktop/scripts/notarize-release.sh` | Zip, submit, staple, verify |
| `desktop/Sources/AgentMeterApp/Platform/BridgeServiceManager.swift` | Helper registration/migration |
| `docs/desktop-app.md` | Installation, setup, usage, settings, troubleshooting |
| `docs/privacy.md` | Exact local data and retention boundary |

---

### Task 1: Recreate and export the production app icon

**Files:**

- Create: `desktop/Artwork/generate_app_icon.swift`
- Create: `desktop/Sources/AgentMeterUI/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: generated PNGs in the same appiconset
- Create: `desktop/Tests/AgentMeterSnapshotTests/AppIconTests.swift`
- Modify: `desktop/Sources/AgentMeterUI/Resources/Assets.xcassets/Contents.json`

**Interfaces:**

- Produces a checked-in asset catalogue consumed by `actool` and SwiftUI previews.

- [ ] **Step 1: Write failing icon integrity tests**

Test the exact required files and pixel dimensions:

```swift
let required: [String: Int] = [
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
]
```

For every PNG assert square dimensions, RGB/RGBA colour space, no embedded text metadata, and
nonempty corner/background pixels appropriate for a macOS rounded-square icon.

- [ ] **Step 2: Implement the deterministic drawing source**

Use AppKit/CoreGraphics to draw the approved graphite rounded square, violet near-complete gauge,
white needle, subtle wireless arcs, and four restrained provider dots. Use exact project palette
values and geometry scaled from a 1024-point canvas. Draw no text, letters, provider logos,
Bluetooth rune, or watermark.

The script takes one required output directory, writes the 1024 master, then produces all required
sizes with high-quality interpolation. It refuses to overwrite a non-icon directory.

- [ ] **Step 3: Generate and inspect every size**

```bash
swift desktop/Artwork/generate_app_icon.swift \
  desktop/Sources/AgentMeterUI/Resources/Assets.xcassets/AppIcon.appiconset
```

Inspect 16, 32, 128, 512, and 1024 pixels in both Light and Dark Finder backgrounds. Confirm the
needle and gauge remain legible at 16 pixels and no provider dot becomes visual noise.

- [ ] **Step 4: Add exact Asset Catalog metadata and run tests**

`Contents.json` maps the ten PNGs to mac idiom 16/32/128/256/512 at 1x/2x. Run:

```bash
swift test --package-path desktop --filter AppIconTests
xcrun actool desktop/Sources/AgentMeterUI/Resources/Assets.xcassets \
  --compile /tmp/agentmeter-assets \
  --platform macosx --minimum-deployment-target 14.0 \
  --app-icon AppIcon --output-partial-info-plist /tmp/agentmeter-assets.plist
```

- [ ] **Step 5: Commit the final icon**

```bash
git add desktop/Artwork/generate_app_icon.swift \
  desktop/Sources/AgentMeterUI/Resources/Assets.xcassets \
  desktop/Tests/AgentMeterSnapshotTests/AppIconTests.swift
git commit -m "feat(mac): add the AgentMeter app icon"
```

---

### Task 2: Package the bridge as a self-contained background app

**Files:**

- Create: `packaging/AgentMeterBridge.spec`
- Create: `packaging/AgentMeterBridge-Info.plist`
- Create: `packaging/AgentMeterBridge.entitlements`
- Create: `desktop/scripts/build-helper.sh`
- Create: `host/tests/test_frozen_entrypoint.py`
- Modify: `host/src/agentmeter_host/__main__.py`
- Modify: `pyproject.toml`
- Modify: `.gitignore`

**Interfaces:**

- Produces `build/helper/AgentMeterBridge.app` with one packaged Python runtime.
- Produces executables `AgentMeterBridge` and `agentmeter-claude-probe` sharing that runtime.
- Consumed by `build-app.sh` in Task 3.

- [ ] **Step 1: Add failing frozen-entrypoint dispatch tests**

```python
def test_entrypoint_dispatches_probe_from_executable_name(monkeypatch) -> None:
    calls = []
    monkeypatch.setattr(sys, "argv", ["agentmeter-claude-probe"])
    monkeypatch.setattr("agentmeter_host.__main__.probe_main", lambda: calls.append("probe") or 0)

    assert dispatch() == 0
    assert calls == ["probe"]
```

Also test `AgentMeterBridge`/`agentmeter` dispatch the normal CLI and no shell is involved.

- [ ] **Step 2: Pin the packaging-only dependency**

Add a `packaging` optional dependency containing a tested PyInstaller major/minor range. Do not add
PyInstaller to normal runtime dependencies. Ignore only `build/helper`, PyInstaller work files,
and release archives.

- [ ] **Step 3: Implement one-folder PyInstaller configuration**

Collect Bleak's CoreBluetooth backend, HTTPX transports, certificates required by current
dependencies, and AgentMeter packages. Exclude test frameworks and unused GUI toolkits. Build one
executable and add a relative symlink named `agentmeter-claude-probe`; dispatch by basename so both
paths share one Python runtime and library directory.

Wrap the one-folder output inside:

```text
AgentMeterBridge.app/Contents/
├── Info.plist
├── MacOS/AgentMeterBridge
├── MacOS/agentmeter-claude-probe -> AgentMeterBridge
└── Frameworks/<PyInstaller runtime files>
```

Use `LSBackgroundOnly=true`, helper bundle ID, version, minimum macOS 14, and an accurate
`NSBluetoothAlwaysUsageDescription`. The helper entitlements grant Bluetooth access and only the
minimum runtime exceptions proven necessary by signed-build tests.

- [ ] **Step 4: Build and smoke-test without the source environment**

```bash
desktop/scripts/build-helper.sh
env -i PATH=/usr/bin:/bin \
  build/helper/AgentMeterBridge.app/Contents/MacOS/AgentMeterBridge --version
env -i PATH=/usr/bin:/bin \
  build/helper/AgentMeterBridge.app/Contents/MacOS/agentmeter-claude-probe --help
```

Copy the helper to a temporary directory outside the repository before the smoke test so imports
cannot resolve source files accidentally. Confirm `otool -L` has no Homebrew Python path.

- [ ] **Step 5: Run host tests and inspect bundle size**

```bash
.venv/bin/pytest host/tests/test_frozen_entrypoint.py -v
.venv/bin/pytest
du -sh build/helper/AgentMeterBridge.app
```

Record bundle size in build output. Fail the script if duplicate Python frameworks or a second
one-folder payload appears.

- [ ] **Step 6: Commit helper packaging**

```bash
git add packaging/AgentMeterBridge.spec packaging/AgentMeterBridge-Info.plist \
  packaging/AgentMeterBridge.entitlements desktop/scripts/build-helper.sh \
  host/src/agentmeter_host/__main__.py host/tests/test_frozen_entrypoint.py \
  pyproject.toml .gitignore
git commit -m "build(mac): package the background bridge"
```

---

### Task 3: Assemble a reproducible unsigned AgentMeter.app

**Files:**

- Create: `packaging/AgentMeter-Info.plist`
- Create: `packaging/AgentMeter.entitlements`
- Create: `desktop/scripts/build-app.sh`
- Create: `desktop/scripts/verify-app.sh`
- Create: `desktop/Tests/AgentMeterAppTests/BundleMetadataTests.swift`
- Modify: `desktop/Package.swift`

**Interfaces:**

- Produces `build/AgentMeter.app` for local installation and signing.

- [ ] **Step 1: Add failing metadata tests**

Assert product name, bundle IDs, semantic version/build number, macOS 14 minimum, copyright,
category, app icon, absence of `LSBackgroundOnly` on the main app, and presence of a concise privacy
description. Assert the nested helper has the helper ID and background-only flag.

- [ ] **Step 2: Implement strict deterministic assembly**

`build-app.sh` uses `set -euo pipefail`, resolves the repository root from its own path, and accepts
`--configuration debug|release` plus `--output`. It validates the output is below the repository's
explicit `build/` directory before replacing it.

Build Swift, compile the asset catalogue with `actool`, copy resources, main executable, Info.plist,
and the complete nested helper into:

```text
AgentMeter.app/Contents/
├── Info.plist
├── MacOS/AgentMeter
├── Resources/Assets.car
└── Library/LoginItems/AgentMeterBridge.app
```

Do not copy Swift source, test fixtures, concept art, Python caches, or provider output.

- [ ] **Step 3: Implement bundle verification**

`verify-app.sh` checks `plutil -lint`, bundle identifiers, executable permissions, required nested
files, icon availability, architecture, minimum deployment target, no absolute repository paths,
no `.py`/`.pyc`/test files outside the frozen helper runtime, and no local signing credentials in
plist or entitlements.

- [ ] **Step 4: Build and launch the unsigned developer app**

```bash
desktop/scripts/build-app.sh --configuration debug --output build/AgentMeter.app
desktop/scripts/verify-app.sh build/AgentMeter.app
open build/AgentMeter.app --args --fake-bridge connected-usb
```

Confirm Dock/menu-bar icon, main window, resources, window close behaviour, and fake mode.

- [ ] **Step 5: Run all automated tests**

```bash
swift test --package-path desktop
.venv/bin/pytest
```

- [ ] **Step 6: Commit app assembly**

```bash
git add packaging/AgentMeter-Info.plist packaging/AgentMeter.entitlements \
  desktop/scripts/build-app.sh desktop/scripts/verify-app.sh \
  desktop/Tests/AgentMeterAppTests/BundleMetadataTests.swift desktop/Package.swift
git commit -m "build(mac): assemble the AgentMeter app bundle"
```

---

### Task 4: Manage login, helper lifecycle, and safe legacy migration

**Files:**

- Create: `desktop/Sources/AgentMeterApp/Platform/BridgeServiceManager.swift`
- Create: `desktop/Sources/AgentMeterApp/Platform/LaunchAtLoginController.swift`
- Create: `desktop/Sources/AgentMeterApp/Platform/LegacyServiceMigrator.swift`
- Create: `desktop/Tests/AgentMeterAppTests/BridgeServiceManagerTests.swift`
- Create: `desktop/Tests/AgentMeterAppTests/LegacyServiceMigratorTests.swift`
- Modify: `desktop/Sources/AgentMeterApp/App/AgentMeterApplication.swift`
- Modify: `desktop/Sources/AgentMeterUI/State/AppModel.swift`
- Modify: `docs/host.md`

**Interfaces:**

- Produces `BridgeServiceManaging` and `LaunchAtLoginManaging` implementations.
- Replaces source-run placeholders from the native app plan in packaged builds.

- [ ] **Step 1: Write failing service lifecycle tests**

Use injected `SMAppService` adapters and process runners. Prove app start registers exactly one
helper, repeated start is idempotent, explicit Quit requests bridge shutdown then unregisters the
helper, Launch at Login maps to `SMAppService.mainApp`, and registration errors surface as
actionable app state.

- [ ] **Step 2: Write failing legacy migration and rollback tests**

```swift
@Test func migrationStopsLegacyBeforeStartingHelperAndRollsBackOnFailure() async {
    let system = RecordingLaunchSystem(legacyLoaded: true, helperStartSucceeds: false)
    let migrator = LegacyServiceMigrator(system: system)

    await #expect(throws: MigrationError.self) { try await migrator.migrate() }

    #expect(system.operations == [
        .bootoutLegacy,
        .registerHelper,
        .waitForIpc,
        .unregisterHelper,
        .bootstrapLegacy,
    ])
    #expect(system.legacyPlistExists)
}
```

Also prove successful migration preserves config/history, deletes only the known legacy plist after
IPC readiness, and leaves one matching process.

- [ ] **Step 3: Implement ServiceManagement adapters**

Use `SMAppService.loginItem(identifier: "com.prabhavalabs.agentmeter.bridge")` for the nested
helper and `SMAppService.mainApp` for app launch at login. Read status before registering or
unregistering. Map requires-approval to a button that opens Login Items settings.

- [ ] **Step 4: Implement transactional legacy migration**

Target only `~/Library/LaunchAgents/com.prabhavalabs.agentmeter.plist` and launchd label
`com.prabhavalabs.agentmeter`. Sequence:

1. Validate plist path, owner, and label.
2. `launchctl bootout` the legacy job.
3. Register the bundled helper.
4. Wait up to ten seconds for a successful IPC `hello`.
5. Remove the known legacy plist only after readiness.
6. On failure, unregister the helper and bootstrap the untouched legacy plist.

Never remove `~/Library/Application Support/AgentMeter`, configuration, history, or logs.

- [ ] **Step 5: Wire startup, window close, and Quit**

App startup performs migration/registration before connecting IPC. Closing all windows keeps app
and helper active. **Quit AgentMeter** sends a bounded shutdown request, unregisters the helper for
the current session, then terminates the app; the persisted main-app login preference can launch
and re-register it at the next login.

- [ ] **Step 6: Run tests and perform migration rehearsal**

```bash
swift test --package-path desktop --filter BridgeServiceManagerTests
swift test --package-path desktop --filter LegacyServiceMigratorTests
desktop/scripts/build-app.sh --configuration debug --output build/AgentMeter.app
```

Rehearse with a temporary home and fake launchctl adapter before touching the installed service.
Then back up and test the real known plist, verify one bridge with `launchctl print`, and verify IPC
and BLE remain connected after the main window closes.

- [ ] **Step 7: Commit service management**

```bash
git add desktop/Sources/AgentMeterApp/Platform \
  desktop/Sources/AgentMeterApp/App/AgentMeterApplication.swift \
  desktop/Sources/AgentMeterUI/State/AppModel.swift \
  desktop/Tests/AgentMeterAppTests/BridgeServiceManagerTests.swift \
  desktop/Tests/AgentMeterAppTests/LegacyServiceMigratorTests.swift docs/host.md
git commit -m "feat(mac): manage the bundled background bridge"
```

---

### Task 5: Sign, notarize, verify, and publish release documentation

**Files:**

- Create: `desktop/scripts/sign-release.sh`
- Create: `desktop/scripts/notarize-release.sh`
- Create: `desktop/scripts/release-check.sh`
- Create: `docs/desktop-app.md`
- Create: `docs/privacy.md`
- Create: `THIRD_PARTY_NOTICES.md`
- Modify: `README.md`
- Modify: `docs/README.md`
- Modify: `docs/setup.md`
- Modify: `docs/development.md`
- Modify: `docs/roadmap.md`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**

- Produces a verified notarized archive and complete end-user/contributor handoff.

- [ ] **Step 1: Implement nested signing with strict verification**

Require `AGENTMETER_SIGNING_IDENTITY` from the environment; never print it. Sign deepest nested
libraries first, then helper executable/bundle, then main executable/bundle with Hardened Runtime
and timestamp. After each level run:

```bash
codesign --verify --deep --strict --verbose=2 build/AgentMeter.app
codesign -d --entitlements :- build/AgentMeter.app
codesign -d --entitlements :- \
  build/AgentMeter.app/Contents/Library/LoginItems/AgentMeterBridge.app
spctl --assess --type execute --verbose=4 build/AgentMeter.app
```

Fail if identifiers or designated requirements do not match expected values.

- [ ] **Step 2: Implement notarization without credential files**

Require `AGENTMETER_NOTARY_PROFILE`, create a deterministic zip with `ditto`, submit with
`xcrun notarytool submit --keychain-profile ... --wait`, staple the app, and validate with
`xcrun stapler validate` plus `spctl`. Preserve the notarization JSON log as a release artifact
after removing account identifiers.

- [ ] **Step 3: Add an unsigned CI packaging smoke test**

On the pinned macOS job, install the packaging optional dependencies in an isolated build venv,
build helper/app unsigned, run `verify-app.sh`, run the frozen helper `--version`, and archive the
unsigned bundle only for CI inspection. Do not attempt signing from pull requests.

- [ ] **Step 4: Write complete public documentation**

Document:

- download/install and first launch;
- Bluetooth permission, pairing, reconnect, forget, and bond clearing;
- menu bar, Overview, Device, Agents, Display, Diagnostics, themes, resizing, and full screen;
- Launch at Login and explicit Quit behaviour;
- USB-only versus optional-battery telemetry and why power consumption can be unavailable;
- provider setup remains in CodexBar;
- history retention/clear and exact privacy boundary;
- legacy service migration and rollback troubleshooting;
- source build, fake bridge, tests, packaging, signing, and contribution workflow.

Add `THIRD_PARTY_NOTICES.md` with the shipped helper/runtime dependencies, versions, licenses, and
required notices. Reference CodexBar as an external prerequisite rather than bundling its code.

Update author/license text only when necessary and keep Nipun Theekshana as the sole author.

- [ ] **Step 5: Run the complete automated release check**

```bash
desktop/scripts/release-check.sh --unsigned
```

The script must run Swift tests/build, host lint/tests, firmware native/build, helper/app assembly,
bundle verification, privacy scans for forbidden fixture/log fields, and git-status cleanliness
checks for generated build output.

- [ ] **Step 6: Run physical and resource acceptance**

On the actual Mac mini and ESP32:

1. Fresh pair and encrypted settings read.
2. Codex, Claude, Cursor, and Gemini refresh/status behaviour.
3. Bidirectional visibility, always-on, full-view, rotation, and supported display settings.
4. Device restart, Mac sleep/wake, Bluetooth toggle, range loss, and bridge restart.
5. USB-only power telemetry and optional battery only when approved hardware is installed.
6. System/Light/Dark; 900 x 620, default, wide, and full screen.
7. Close/reopen window while menu synchronization continues.
8. Explicit Quit leaves no bridge/provider child; next login preference restores operation.
9. Eight-hour menu-only soak and repeated open/close/reconnect loop with no monotonic RSS, CPU,
   file-descriptor, or child-process growth.

Record Activity Monitor/`ps` baselines and hardware results in the pull-request verification notes.

- [ ] **Step 7: Build the signed notarized candidate**

```bash
desktop/scripts/build-app.sh --configuration release --output build/AgentMeter.app
desktop/scripts/sign-release.sh build/AgentMeter.app
desktop/scripts/notarize-release.sh build/AgentMeter.app
desktop/scripts/release-check.sh --signed build/AgentMeter.app
```

- [ ] **Step 8: Commit release tooling and documentation**

```bash
git add desktop/scripts/sign-release.sh desktop/scripts/notarize-release.sh \
  desktop/scripts/release-check.sh docs/desktop-app.md docs/privacy.md \
  THIRD_PARTY_NOTICES.md README.md \
  docs/README.md docs/setup.md docs/development.md docs/roadmap.md \
  .github/workflows/ci.yml
git commit -m "docs: add macOS installation and release workflow"
```

## Final completion gate

The objective is complete only when current evidence proves all of these:

- the clean app installs without Python or source files;
- signing, Hardened Runtime, notarization, stapling, and Gatekeeper verification pass;
- one managed helper owns BLE and provider collection;
- legacy migration and rollback are verified without losing user data;
- every supported device setting is bidirectional and revision-confirmed;
- required connection, provider, firmware, power, battery, and telemetry states are visible;
- menu bar, login, window-close, resize, full-screen, System/Light/Dark, keyboard, and VoiceOver
  behaviours pass;
- USB-only hardware reports no installed battery and no fabricated power consumption;
- full automated, hardware, clean-install, and eight-hour resource gates pass;
- public documentation and sole-author metadata are correct;
- firmware updating, cloud access, and multiple devices remain absent from v1.
