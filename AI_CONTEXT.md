# Project Context

> Audience: future AI assistants working on this repository.
>
> Last verified: 2026-07-28
>
> Evidence rule: use source code and CodeGraph for current implementation facts, Active documents
> for product/protocol/manual decisions, and Historical documents only for traceability. Anything not
> established by repository evidence is marked 「待确认」.

## Project Overview

BoltStar is a Flutter mobile application for operating smart photo frames. The current repository is
connected to the real BoltFox backend and real BLE devices; it is not a local-data prototype.

The product currently covers:

- email registration/login, WeChat mobile login, profile maintenance, logout, and account deletion;
- frame discovery, binding, identity verification, connection, slideshow settings, storage clearing,
  unbinding, and OTA;
- camera/gallery selection, multi-image preview and editing, server-side six-color frame conversion,
  BLE image transfer, and backend record updates;
- gallery, casting history, FAQ/operation guides, and Simplified Chinese, Traditional Chinese,
  English, and Japanese content;
- BLE engineering diagnostics, an in-app iOS transfer performance self-test, and Android crash
  evidence capture;
- an implemented AI chat/image-enhancement subsystem whose normal production entry is currently
  disabled by `kAiEntryEnabled=false`; a debug entry remains.

The declared product release targets are Android and iOS. The Web, Windows, macOS, and Linux
directories are Flutter-generated shells and are not current product release targets.
OpenHarmony/HAP is not integrated.

## Tech Stack

### Application

- Flutter application with Dart SDK constraint `^3.11.5`.
- Package/application name: `BoltStar`; repository version: `1.0.0+1`.
- Flutter channel recorded by `.metadata`: `stable`.
- State is owned at the application root through the shared `PhotoFrameState` and `BleController`;
  the project does not declare a third-party state-management framework.
- UI uses Flutter Material/Cupertino components and `flutter_localizations`.
- Static analysis uses `flutter_lints ^6.0.0`.

### Main Dart dependencies

| Dependency | Declared version | Purpose |
| --- | --- | --- |
| `flutter_blue_plus` | `^2.3.8` | BLE scanning, GATT connection, MTU, writes, and notifications |
| `http` | `^1.2.2` | BoltFox, seekink, and AI HTTP calls |
| `http_parser` | `^4.0.2` | Explicit multipart media types |
| `crypto` | `^3.0.6` | Lowercase 32-character MD5 for password-compatible requests |
| `image_picker` | `^1.1.2` | Camera and gallery source selection |
| `image` | `4.9.1` | Isolate-side crop/resize and JPEG encoding |
| `cached_network_image` | `^3.4.1` | Memory/disk-backed network image display |
| `flutter_cache_manager` | `^3.4.1` | Explicit disk cache cleanup |
| `shared_preferences` | `^2.3.2` | Lightweight local settings and BLE tuning persistence |
| `fluwx` | `^6.0.0` | WeChat mobile-app authorization |
| `package_info_plus` | `^10.2.1` | Installed application version |
| `url_launcher` | `^6.3.0` | Browser/store navigation |
| `image_cropper` | `^12.2.1` | Still declared and registered natively, but not used by the current cast preview flow |

`pubspec.lock` currently resolves packages through `https://pub.flutter-io.cn`.

### Android

- Application ID and namespace: `com.boltfox.boltstar`.
- Android Gradle Plugin `8.11.1`, Kotlin Android plugin `2.2.20`, Gradle `8.14`.
- Java/Kotlin JVM target: 17.
- `compileSdk`, `minSdk`, and `targetSdk` are inherited from the installed Flutter toolchain rather
  than fixed to numeric values in the repository.
- Native code is Kotlin. It provides the Flutter device method channel, a BLE connected-device
  foreground service, wake-lock lifetime handling, and Android crash logging.
- The main manifest declares version-specific Bluetooth/media permissions, camera, network,
  foreground-service, wake-lock, and notification permissions.
- The Android renderer is deliberately kept on a compatibility path:
  `EnableImpeller=false` plus `ImpellerBackend=opengles`, due to recorded Vulkan-driver crashes on
  some devices. Do not remove these flags without release-device regression evidence.

### iOS

- Deployment target: iOS 13.0.
- CocoaPods-based Flutter integration; native code is Swift.
- The device method channel is also implemented by `Runner/AppDelegate.swift`.
- `UIBackgroundModes` contains `bluetooth-central`.
- Bluetooth, photo-library, camera, and location usage descriptions are present.
- WeChat URL schemes/universal-link configuration is build-parameter dependent; see the setup and
  release runbooks.
- Android-style persistent crash-file capture is not implemented on iOS. BLE performance diagnostics
  keep a bounded in-memory log for the hidden self-test page.

### Environment status

- The repository does not pin a human-readable Flutter release number with FVM or an equivalent
  version manager: 「待确认」 which Flutter release all development machines must use.
- Android/iOS signing material and WeChat production values are intentionally external to source
  control.

## Architecture Overview

BoltStar uses a feature-first Flutter layout with small cross-cutting application, state, network,
device, route, localization, and shared-infrastructure layers.

```text
main.dart
  -> BoltStarApp
       -> PhotoFrameState
       -> BleController
       -> lifecycle / routing / localization
       -> AppShell
            |-> HomePage
            `-> MinePage

UI / PhotoFrameState
  |-> BoltFoxApi -> ApiClient -> BoltFox backend
  |-> DitheringApi -----------> seekink six-color conversion service
  |-> BoltStarAiApi ----------> independent AI service
  `-> BleController
        -> FrameBleClient
          -> FrameProtocol / FrameDeviceProtocol
            -> flutter_blue_plus / platform-native support
```

Architectural boundaries:

- `BoltStarApp` creates and owns the shared state/controller and observes application lifecycle.
- `PhotoFrameState` is the UI-facing business facade for session, profile, devices, gallery, casting
  records, FAQ, and stateful backend actions.
- `BleController` is the only shared physical-device session facade. Pages must not create their own
  long-lived `FrameBleClient`.
- `FrameBleClient` owns GATT discovery, notifications, command serialization, MTU/chunk sizing,
  image packet windows, cumulative ACK handling, retries, and transfer telemetry.
- `ServerImageProjectionService` coordinates backend record upload, seekink conversion, BLE transfer,
  rollback, and result reporting.
- Named routes live in `AppRoutes`; parameter-heavy flows may use `AppPageRoute` directly. Routing
  should dispatch pages, not absorb connection, deletion, permission, or OTA business rules.
- BoltFox, seekink, and BoltStar AI have different authentication and response contracts and must
  remain separate service abstractions.

## Directory Structure

```text
.
|-- AI_CONTEXT.md             # This AI-oriented current-context document
|-- AGENTS.md                 # Repository-level AI execution and CodeGraph rules
|-- lib/
|   |-- main.dart             # Process entry and early cache/tuning initialization
|   `-- src/
|       |-- app/              # Root app widget and theme
|       |-- device/           # BLE controller, client, protocol, identity, lease, OTA
|       |-- features/         # Product domains and their presentation/flow code
|       |-- network/          # HTTP clients, APIs, DTO parsing, session, exceptions
|       |-- routes/           # Route registration
|       |-- shared/           # Localization, reusable widgets, permissions, caches, temp files
|       |-- native_device_api.dart
|       `-- state.dart        # Shared application/business state facade
|-- assets/                   # Product images and battery assets
|-- test/                     # Dart/Flutter unit and widget tests
|-- android/                  # Android host, permissions, signing, service, and crash logging
|-- ios/                      # iOS host, CocoaPods, entitlements, URL schemes, and permissions
|-- web/ windows/ macos/ linux/
|                             # Generated shells, not current release targets
`-- docs/
    |-- README.md             # Documentation index, lifecycle, and maintenance policy
    |-- PROJECT_OVERVIEW.md   # Human-readable active project overview
    |-- architecture/         # Current architecture/protocol decisions
    |-- integration/          # External and cross-client integration knowledge
    |-- runbooks/             # Build, release, and diagnostic procedures
    |-- content/              # User-facing multilingual source content
    |-- generated/            # Generated/platform-provided documentation
    `-- history/YYYY-MM/      # Frozen audits, ledgers, and change records
```

Inside `lib/src/features/`, the current domains are `account`, `ai`, `cast`, `devices`, `gallery`,
`guide`, `home`, `mine`, `settings`, and `shell`. There is no separate `features/album` or
`features/demo` domain.

## Core Modules

| Module | Responsibility | Key files |
| --- | --- | --- |
| Bootstrap and app root | Early initialization, splash/root transition, session restoration, lifecycle observation, shared state/controller ownership, theme, force-update and crash prompts | `lib/main.dart`, `lib/src/app/bolt_star_app.dart`, `lib/src/app/app_theme.dart` |
| Shared business state | Session/profile, devices, selected target, gallery, casting records, FAQ, user actions, API error mapping, session-expiry reset | `lib/src/state.dart` |
| Routing and shell | Named route dispatch and two-tab Home/Mine shell | `lib/src/routes/app_routes.dart`, `lib/src/features/shell/presentation/` |
| Network core | Common BoltFox parameters, token/session state, response parsing, uploads, exceptions, API row parsing | `lib/src/network/api_client.dart`, `api_session.dart`, `api_rows.dart`, `api_exception.dart` |
| BoltFox API | Account, product, user-device, gallery, casting-record, version, upload, and seekink-token endpoints | `lib/src/network/boltfox_api.dart` |
| External services | seekink binary conversion/token refresh and independent BoltStar AI calls | `lib/src/network/dithering_api.dart`, `lib/src/network/boltstar_ai_api.dart` |
| BLE session and protocol | Permissions, scan, one-session ownership, full-ID verification, GATT commands, image transfer, ACK/retry behavior, connection lease, performance tuning, OTA | `lib/src/device/ble_controller.dart`, `lib/src/device/ble/device_ble.dart`, `lib/src/device/ble/frame_protocol.dart`, `lib/src/device/frame_device_protocol.dart`, `lib/src/device/serial_match.dart`, `lib/src/device/ble_connection_lease.dart`, `lib/src/device/ble/ota_ble.dart` |
| Device feature | Bind/search/found/not-found flows, list/detail, carousel, clear, unbind, OTA, BLE debug, and performance diagnostics | `lib/src/features/devices/` |
| Cast feature | Source selection, persistent preview editor, strict device-resolution export, backend conversion, BLE projection, progress/results, recast | `lib/src/features/cast/` |
| Account feature | Email/WeChat auth, registration, password/email/profile maintenance, local email history | `lib/src/features/account/` |
| Gallery feature | User image list, device filtering, delete, display refresh, and recast entry | `lib/src/features/gallery/` |
| Home and Mine | Primary product entry points, selected-device summary, account statistics, navigation cards | `lib/src/features/home/`, `lib/src/features/mine/` |
| Settings and guide | Language, legal documents, version/update, logout/deletion, FAQ pagination and HTML-subset rendering | `lib/src/features/settings/`, `lib/src/features/guide/`, `lib/src/shared/l10n/` |
| AI feature | Sessions, chat history, up to four public image URLs, image compression/upload/enhancement, localized error mapping | `lib/src/features/ai/`, `lib/src/network/boltstar_ai_api.dart` |
| Resource/native infrastructure | Image-cache privacy cleanup, temporary-file cold-start sweep, permission/native bridge, Android foreground service and crash capture | `lib/src/shared/image_cache_cleanup.dart`, `lib/src/shared/temp_cache_sweeper.dart`, `lib/src/native_device_api.dart`, `android/app/src/main/kotlin/com/boltfox/boltstar/`, `ios/Runner/AppDelegate.swift` |

## Data Flow

### 1. Startup and session restoration

```text
main()
  -> configure Flutter image-cache limits
  -> sweep registered cast/recast temporary-file prefixes
  -> load persisted BleTuning values
  -> configure BLE plugin logging
  -> run BoltStarApp
       -> create shared PhotoFrameState and BleController
       -> show splash for the configured 1.8 seconds
       -> restore language/session in parallel
       -> root login gate selects authenticated or unauthenticated UI
       -> check crash evidence and required application update
```

Session-expiry handling is idempotent. A BoltFox 401/406 clears the API session, resets user-owned
state, clears image caches, and lets the root login gate return the user to authentication.

### 2. BoltFox request flow

```text
Page
  -> PhotoFrameState action
  -> BoltFoxApi method
  -> ApiClient
       -> inject device / terminal / language / userToken
       -> HTTP request or multipart upload
       -> parse retCode / retMsg / retData
  -> map DTO rows into UI models
  -> notify shared-state listeners
```

`terminal` is Android `1`, iOS `2`, and mini-program `3`. Password-compatible requests use lowercase
32-character MD5. AI requests do not pass through this response wrapper.

### 3. Device binding

```text
Permission gate
  -> load product/broadcast information
  -> BLE scan and incrementally display candidates
  -> user selects a ScanResult (default UI choice is strongest RSSI)
  -> BleController establishes the persistent physical session
  -> read device core information, including the protocol identity
  -> resolve required productId from product model/screen/scan data
  -> BoltFoxApi.addUserProduct(productId, name, serial)
  -> refresh bound-device list
```

Binding aborts if `productId` cannot be resolved; it must not send an incomplete backend request.
The scan-session `remoteId`, user-visible broadcast device ID, editable device name, and protocol
full device ID are different concepts.

### 4. Connecting to an already-bound device

```text
Snapshot the user-selected backend device record
  -> reuse only an active session whose verified full ID and screen type match
  -> otherwise request permission and end any different active session
  -> scan up to the bounded candidate limit
  -> filter by anchored short-ID compatibility and screen type
  -> connect GATT and read command 0x01 full identity
  |    -> match: register verified session and read device state
  `    -> mismatch: disconnect, exclude remoteId, continue scanning
```

Current code limits same-short-ID verification to four candidates and uses 12-second scan windows.
An editable device name is never identity evidence.

### 5. Image selection, editing, and projection

```text
Camera/gallery selection
  -> CastPreviewPage persistent editor
       -> pan / zoom / rotate / portrait-landscape viewport
       -> bake edited canvas at exact device pixel dimensions
       -> or center-cover crop an unedited source to exact device dimensions
       -> encode JPEG at quality 92 in an isolate
  -> CastingProgressPage snapshots target device identity
  -> reconnect that exact target if necessary
  -> ServerImageProjectionService
       -> wait for device transfer state to become idle when busy/pending
       -> obtain backend image record/original upload and seekink six-color 4bpp frame
       -> select a free physical image slot
       -> FrameBleClient sends windowed BLE packets and waits for cumulative ACKs
       -> on success, update backend record with the real imgIndex
       -> on a later per-image failure, attempt device-side slot rollback
  -> refresh connected-device capacity/mask
  -> on overall success, refresh account image count
```

The progress bar is per current image; `current/total` represents the batch. Busy/command-pending
device state is retried for up to 12 seconds at 800 ms intervals before becoming a user-visible
failure. Failure classification uses `FrameBleErrorKind`; it must not depend on matching translated
message substrings.

### 6. Gallery deletion and device refresh

- The backend gallery response is already user-scoped by `userToken`; state must not re-filter it by
  a concurrently refreshed local owner ID.
- Gallery ordering is newest-first, with numeric `uProductImgId` as a deterministic tie-breaker when
  timestamps are absent/equal.
- Delete (`0x12`) and display refresh (`0x24`) resolve the physical slot through the same logic:
  prefer a valid real `imgIndex` that is occupied in the device mask; only legacy records without an
  index may use constrained inference.
- Slot `0` is valid. Missing/invalid slot is represented by `-1`, never by truthiness.

### 7. BLE/application lifecycle

```text
Connected foreground session
  -> start Android connected-device foreground service
  -> active connect/transfer/OTA task protects the lease
  -> app leaves foreground:
       screen on  -> 15-minute grace period
       screen off -> 30-minute grace period
  -> lease expiry
       -> disconnect GATT
       -> cancel notifications/session state
       -> stop foreground service and release wake lock
```

The lease is swept every 60 seconds. Returning to foreground reconciles memory state with the real
BLE connection because background disconnect callbacks may have been missed.

## Important Design Decisions

1. **One shared state and one BLE session.** Pages consume the root-owned `PhotoFrameState` and
   `BleController`; competing page-owned clients would corrupt session identity and callbacks.
2. **Physical identity is protocol identity.** Broadcast short ID and screen type only select
   candidates. Command `0x01` full ID is required for final verification when the backend stores a
   full six-byte ID.
3. **The selected target is immutable during an async operation.** Connection, projection, delete,
   clear, and OTA flows snapshot the backend device ID and must not silently switch when UI selection
   changes.
4. **Only one active physical connection is supported.** Connecting another device first tears down
   the old GATT/session state.
5. **Three HTTP services keep separate contracts.** BoltFox, seekink, and BoltStar AI do not share a
   response model merely because all use HTTP.
6. **seekink token recovery is bounded.** Cache the token for the session; on a conversion 401,
   request a forced token refresh once with `isNewLogin=1` and retry once, avoiding loops.
7. **Real device slot is persisted.** Successful projection records the device's physical
   `imgIndex`; `0` is valid, `-1` means unknown, and device mask validation protects destructive
   commands.
8. **Current preview editing is canvas-based.** Edited output is baked in a persistent custom editor;
   unedited images are center-cover cropped. Both paths export exact device pixels as JPEG quality
   92. The native `image_cropper` path is legacy for this flow.
9. **Horizontal output follows the established 270-degree rule.** Do not change rotation direction
   without comparing actual frame output and the mini-program baseline.
10. **Resource cleanup is part of privacy.** Logout, successful account deletion, and session expiry
    clear decoded-memory and disk image caches. Cast temporary files are swept at cold start because
    their final consumer cannot be identified reliably during a live flow.
11. **BLE tuning values are diagnostic runtime controls.** Defaults remain pace `3 ms`, floor
    `0 ms`, window `10`, automatic platform transfer interval, unacknowledged writes. Experiments
    persist across launches and must be reset after testing.
12. **Android renderer compatibility flags are intentional.** They represent a device-crash
    mitigation, not template noise.
13. **The mini-program is a behavioral baseline, not an instruction to erase platform differences.**
    Current intentional App differences are documented in `docs/integration/APP_VS_MINIPROGRAM.md`.
14. **Documentation has lifecycle semantics.** Active documents define current long-lived knowledge;
    Historical documents are frozen evidence; Superseded documents cannot be used as current rules.

## Development Rules

1. Read `AGENTS.md` before work. This repository is used from office, home, and remote environments;
   Git is the only shared source of truth.
2. If `.codegraph/` exists, use CodeGraph before grep/manual file traversal for architecture,
   call-chain, dependency, impact, or unfamiliar-code questions.
3. Run `codegraph sync` after pulling changes. Never commit `.codegraph/`; it is a per-machine,
   reproducible cache.
4. For current code location/callers, trust source plus CodeGraph. For product, protocol, release, and
   manual decisions, use the relevant Active document. Never treat `docs/history/` as current truth.
5. Preserve the root-owned `PhotoFrameState` and `BleController` boundaries. UI pages should not
   create replacement business-state or long-lived BLE-client instances.
6. Never use device name as physical identity. Preserve full-ID verification, screen-type conflict
   checks, wrong-candidate disconnect, and candidate exclusion behavior.
7. Preserve target-device snapshots through asynchronous business flows.
8. Handle `imgIndex` with explicit numeric comparisons. `0` is a valid slot; unknown is `-1`.
9. Keep BoltFox, seekink, and AI authentication/response handling separate. Do not display AI
   service `detail` directly to users.
10. User-visible text belongs in `AppL10n`. Engineering-only debug pages may be explicitly exempt.
11. New cast/recast temporary-file prefixes must be registered in `TempCacheSweeper` and documented
    in `docs/architecture/RESOURCE_LIFECYCLE.md`.
12. Do not change BLE pacing, window, MTU/chunk, ACK, connection-interval, or timeout values as a
    cosmetic refactor. Use the iOS performance runbook and real hardware evidence.
13. Restore `BleTuning` defaults after diagnostics; saved experimental values affect ordinary casts.
14. Do not remove Android foreground-service/wake-lock or renderer configuration without verifying
    lifecycle deadlines and affected release devices.
15. Regular project documentation belongs under `docs/`. `AGENTS.md` and this explicitly requested
    `AI_CONTEXT.md` are root-level AI control/context exceptions.
16. Update the Active owner document when a change alters architecture, API contracts, BLE identity,
    slot semantics, resource lifecycle, cross-client behavior, platform setup, release steps, or
    user-facing multilingual content.
17. Normal validation is:

    ```bash
    dart analyze lib test
    flutter test
    ```

    BLE transfer, connection intervals, OTA, camera/gallery, WeChat login, background behavior, and
    release-only platform configuration require real-device validation.
18. Android release builds require complete `android/key.properties`; do not add signing secrets to
    Git. iOS release setup and WeChat values are external build inputs.

## Known Risks

- **Critical integration paths have limited automated coverage.** CodeGraph reports no direct tests
  covering `ServerImageProjectionService.castImages`, bound-device connection orchestration,
  `PhotoFrameState.bindDevice`, or the BLE debug/performance pages. Existing tests focus on protocol
  parsing, serial matching, connection leases, API rows, localization/widgets, and auth UI.
- **Same-short-ID devices can cross-connect if identity rules regress.** The full-ID verification and
  wrong-candidate exclusion path is safety-critical.
- **Backend slot uniqueness is not confirmed.** If two records for one device can retain the same
  `imgIndex`, an old "ghost" record may point at a newly reused physical slot and delete/display the
  wrong image. The client mask check cannot distinguish this case.
- **Partial projection failures can leave split state.** Backend record creation, binary conversion,
  BLE storage, backend success update, and device rollback cross three systems; rollback failure can
  leave orphaned device slots or records.
- **iOS BLE performance still contains hardware/firmware-dependent unknowns.** Actual connection
  interval acceptance, firmware parameter ranges, ten-packet receive buffering, and
  `writeWithoutResponse` backpressure require real-device measurement.
- **BLE background behavior is platform-sensitive.** Android depends on a foreground service and
  wake lock; iOS depends on CoreBluetooth restoration/runtime behavior. Simulators cannot validate
  the product BLE flow.
- **Runtime Flutter version is not repository-pinned.** Flutter-managed Android SDK defaults can
  change when developers use different stable releases.
- **Legacy cropper configuration remains.** `image_cropper` and Android `UCropActivity` are still
  declared although current cast editing does not use them. Removing or reviving them requires an
  explicit dependency/configuration audit.
- **Android renderer flags are a compatibility workaround.** A future Flutter engine may ignore the
  Skia fallback, and removing the GLES fallback may reintroduce vendor-GPU crashes.
- **WeChat iOS scene callback behavior needs release-device regression.** The runbook records a
  possible scene-lifecycle compatibility issue if authorization callbacks disappear.
- **iOS diagnostic persistence is limited.** Android has crash-file capture; iOS BLE diagnostics are
  in memory unless collected through platform tooling.
- **The BoltFox user token is currently included in query parameters.** This follows the backend
  contract but creates log-redaction risk.
- **Firmware downloads have no confirmed hash field.** Client-side integrity verification is not
  available until the backend supplies MD5/SHA-256 metadata.
- **FAQ and gallery have non-obvious loading semantics.** FAQ must paginate by
  `recordCount/pageCount`; an empty response must replace the old language. Gallery must not
  re-filter backend-scoped rows by a concurrently changing local user ID.
- **AI is present but production-disabled.** Enabling it requires contract, session, error-code,
  image-message, privacy, and release-entry validation, not only changing the feature flag.
- **Documentation governance currently says `AGENTS.md` is the only root Markdown exception.**
  This file was created at the root by explicit user instruction, so `docs/README.md` should be
  reconciled in a later documentation-only change.
- **The current working tree may contain unrelated documentation moves and `.gitignore` changes.**
  Future assistants must inspect `git status` and preserve user changes instead of normalizing or
  reverting them.

## Documentation Map

### Root AI documents

| Document | Role |
| --- | --- |
| `AGENTS.md` | Mandatory repository execution rules, multi-machine assumptions, and CodeGraph policy |
| `AI_CONTEXT.md` | Fast current project context for future AI assistants; not a user README |

### Active project knowledge

| Document | Role |
| --- | --- |
| `docs/README.md` | Documentation index, lifecycle, source-of-truth rules, update triggers, and maintenance rhythm |
| `docs/PROJECT_OVERVIEW.md` | Human-readable product scope, release targets, capabilities, and basic commands |
| `docs/architecture/PROJECT_STRUCTURE.md` | Current code/module/state/route/network/BLE/cast/test architecture |
| `docs/architecture/API_INTEGRATION.md` | BoltFox, seekink, and BoltStar AI contracts and service boundaries |
| `docs/architecture/BLE_CONNECTION_AND_IDENTITY.md` | Single-session, candidate selection, full-ID verification, battery, and lifecycle invariants |
| `docs/architecture/IMAGE_SLOT_INDEX.md` | Physical `imgIndex` persistence, parsing, lookup, fallback, and known consistency gaps |
| `docs/architecture/RESOURCE_LIFECYCLE.md` | Image cache, account isolation, temp files, memory pressure, BLE lease, and process reclamation |
| `docs/integration/APP_VS_MINIPROGRAM.md` | Current App/mini-program capability matrix and intentional platform differences |
| `docs/integration/WECHAT_LOGIN_SETUP.md` | WeChat Open Platform app registration and native Android/iOS configuration |
| `docs/runbooks/BUILD_RELEASE.md` | Android/iOS build, signing, placeholders, release regression, and store checks |
| `docs/runbooks/IOS_BLE_PERFORMANCE.md` | In-app/self-hosted BLE diagnostics, metrics, controls, and real-device decision tree |
| `docs/content/操作手册与常见问题-四语种.md` | Multilingual FAQ/manual source content for operations/backend entry |
| `docs/generated/IOS_LAUNCH_IMAGE.md` | Centralized generated/platform launch-image asset notes |

### Historical knowledge

`docs/history/2026-07/` contains implementation ledgers, audits, past comparisons, and snapshots.
Use these only to understand why a current decision exists. The Active replacement must be consulted
before applying any historical conclusion.

Current history groups include:

- legacy project/API/cross-client snapshots;
- 2026-07-17 optimization and performance analysis;
- 2026-07-19 bug-fix and FAQ rounds;
- 2026-07-20 resource and single-connection audits;
- 2026-07-22 iOS projection-performance changes;
- 2026-07-27 device-identity/battery review;
- the July runbook change digest.

## AI Working Notes

1. At the time of this document's creation, `codegraph status` reports an up-to-date index:
   143 indexed files, 3,538 nodes, 9,840 edges, 11.64 MB, with no pending synchronization.
2. High-value first CodeGraph queries:
   - `main.dart BoltStarApp PhotoFrameState AppShell AppRoutes`
   - `BleController FrameBleClient serial_match connectBoundDevice`
   - `ServerImageProjectionService CastingProgressPage CastImageEditor`
   - the exact symbol being changed plus its page/state/API caller
3. CodeGraph answers current symbol/call-path questions; it does not replace compiler, tests, release
   builds, or physical-device validation.
4. Re-check `codegraph status` after pulling or substantial edits. The index is local and can lag a
   filesystem write briefly.
5. For an unfamiliar task, read in this order:
   `AGENTS.md` -> this file -> `docs/README.md` -> the relevant Active owner document -> CodeGraph
   source/call path. Read Historical files only when the reason/sequence of a decision is necessary.
6. Avoid copying volatile source listings into Markdown. Record stable constraints, external
   contracts, rationale, runbooks, and unresolved decisions; leave symbol locations/callers to
   CodeGraph.
7. If code contradicts an Active architecture document:
   - use source plus CodeGraph for what executes now;
   - do not silently discard the documented product/protocol intent;
   - identify whether the code or the document is stale, then update the correct owner artifact in
     the authorized scope.
8. Preserve unrelated worktree changes. This repository may be edited from multiple machines, and
   local state is not shared until committed/pushed through Git.

## Information Sources

### CodeGraph

- Current index status from `codegraph status`.
- Entry/state/route call graph: `main.dart`, `BoltStarApp`, `PhotoFrameState`, `AppShell`,
  `AppRoutes`.
- Network/service relationships: `ApiClient`, `BoltFoxApi`, `DitheringApi`, `BoltStarAiApi`.
- BLE identity and lifecycle: `BleController`, `FrameBleClient`, `BleConnectionLease`,
  `serial_match.dart`.
- Projection call path: `CastingProgressPage`, `ServerImageProjectionService.castImages`,
  `CastImageEditor`, transfer information/rollback paths.
- Binding call path: `BindDeviceFlowPage`, `PhotoFrameState.bindDevice`,
  `BoltFoxApi.addUserProduct`.

### Source and configuration

- `pubspec.yaml`, `pubspec.lock`, `.metadata`, `analysis_options.yaml`.
- `lib/main.dart`, `lib/src/app/`, `lib/src/state.dart`, `lib/src/routes/`.
- `lib/src/network/`, `lib/src/device/`, and the feature directories listed above.
- `android/settings.gradle.kts`, `android/app/build.gradle.kts`,
  `android/app/src/main/AndroidManifest.xml`, and Android Kotlin host code.
- `ios/Podfile`, `ios/Runner/Info.plist`, `ios/Runner.xcodeproj/project.pbxproj`,
  `ios/Runner/AppDelegate.swift`.
- Existing files under `test/`.

### Active Markdown

- `docs/README.md` and `docs/PROJECT_OVERVIEW.md`.
- All five documents under `docs/architecture/`.
- Both documents under `docs/integration/`.
- Both documents under `docs/runbooks/`.
- The documentation index entries for `docs/content/` and `docs/generated/`.

## Unconfirmed Items

- 「待确认」 The exact Flutter release all development and build machines are expected to use.
- 「待确认」 The numeric Android `minSdk`, `compileSdk`, and `targetSdk` after resolution by the
  agreed Flutter toolchain.
- 「待确认」 The complete current Swagger field set returned by `getXTYUserToken`.
- 「待确认」 Whether the backend enforces one active record per device plus physical `imgIndex`.
- 「待确认」 Whether the latest deployed BoltStar AI API still matches current session creation,
  error codes, and image-message structures.
- 「待确认」 Whether firmware builds in production accept the requested iOS connection interval,
  use Apple-compatible min/max ranges, and are limited to a ten-packet receive buffer.
- 「待确认」 Whether the installed iOS BLE plugin path provides effective backpressure for every
  `writeWithoutResponse` device/runtime combination.
- 「待确认」 Production signing credentials, WeChat App ID/universal link/associated-domain state,
  and store-account configuration; these are external and must not be inferred.
- 「待确认」 Current real-device release results for login, WeChat callbacks, BLE scan/connect,
  multi-image projection, OTA, background/lock-screen behavior, and iOS throughput.
- 「待确认」 Whether `99999@qq.com` in the release checklist is the actual customer-service address.
- 「待确认」 Whether `image_cropper`/uCrop can now be removed, or remains reserved for a planned
  non-cast flow.
- 「待确认」 Whether the build runbook's CocoaPods lockfile warning is still current on every build
  machine.

## Follow-up Recommendations

1. Reconcile `docs/README.md` so its root-Markdown exception list includes this explicitly requested
   `AI_CONTEXT.md`.
2. Pin the Flutter SDK version across office/home/CI environments, then replace the related
   「待确认」 items with exact resolved Android SDK values.
3. Add orchestration tests around projection success/partial failure/rollback, bound-device
   connection candidate exclusion, binding `productId` resolution, and session-expiry cleanup.
4. Close the backend `device + imgIndex` uniqueness question; document the enforced rule and add a
   regression test for slot reuse/ghost records.
5. Run and record the iOS BLE A/B/C self-test on representative hardware, including MTU, chunk,
   retries, throughput, and connection-interval evidence.
6. Audit the unused `image_cropper` dependency and `UCropActivity` registration as one explicit
   change; do not remove only one side.
7. Treat this file as a concise current-context snapshot: update it when product scope, top-level
   architecture, critical invariants, platform targets, or major unresolved risks change. Keep
   detailed contracts and runbooks in their existing Active owner documents rather than duplicating
   them here.
