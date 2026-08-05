# Project Context

> Audience: future AI assistants working on this repository.
>
> Last verified: 2026-07-30
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
- an implemented AI chat/image-enhancement subsystem with per-user AI-service consent and a
  multilingual legal page; its normal production entry is currently disabled by
  `kAiEntryEnabled=false`, while a debug entry remains.

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
| `image_picker_android` | `^0.8.13+17` | Enables Android system Photo Picker for all gallery entry points |
| `image_picker_platform_interface` | `^2.11.1` | Access to the registered picker implementation during startup configuration |
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
- `BleNativeProbe.kt` and its one-line `MainActivity` registration are **temporary**: a native
  versus `flutter_blue_plus` connection A/B probe reachable only from the hidden performance
  self-test page. It is not part of the production connection path and is deleted together with
  `lib/src/device/ble/ble_ab_benchmark.dart` and the self-test page card once the comparison is
  decided. Removal checklist: `docs/history/2026-07/2026-07-30-安卓原生连接AB对比.md`.
- The main manifest declares version-specific Bluetooth permissions, camera, network,
  foreground-service, wake-lock, and notification permissions. It deliberately does not declare
  `READ_MEDIA_IMAGES`, `READ_MEDIA_VISUAL_USER_SELECTED`, or `READ_EXTERNAL_STORAGE`.
- `main()` enables `ImagePickerAndroid.useAndroidPhotoPicker` before `runApp()`. Gallery and avatar
  selection receive URI access only for user-selected images and must not be preceded by a
  photo-library permission request.
- The Android renderer is deliberately kept on a compatibility path:
  `EnableImpeller=false` plus `ImpellerBackend=opengles`, due to recorded Vulkan-driver crashes on
  some devices. Do not remove these flags without release-device regression evidence.

### iOS

- Deployment target: iOS 13.0.
- CocoaPods-based Flutter integration; native code is Swift.
- The device method channel is also implemented by `Runner/AppDelegate.swift`.
- `UIBackgroundModes` contains `bluetooth-central`.
- Bluetooth, photo-library, camera, and location usage descriptions are present.
- The WeChat URL Scheme and mobile AppID are fixed to `wx4cf0c5f38a70d0bc`; the Universal Link
  remains a build/external-platform input. See the setup and release runbooks.
- Android-style persistent crash-file capture is not implemented on iOS. BLE performance diagnostics
  keep a bounded in-memory log for the hidden self-test page.

### Environment status

- The repository does not pin a human-readable Flutter release number with FVM or an equivalent
  version manager: 「待确认」 which Flutter release all development machines must use.
- Android/iOS signing material, the WeChat AppSecret, and the iOS Universal Link are intentionally
  external to source control. The non-secret mobile AppID is fixed in source.

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
| BLE session and protocol | Permissions, scan, one-session ownership, full-ID verification, GATT commands, image transfer, ACK/retry behavior, connection lease, performance tuning, OTA | `lib/src/device/ble_controller.dart`, `lib/src/device/ble/device_ble.dart`, `lib/src/device/ble/frame_protocol.dart`, `lib/src/device/frame_device_protocol.dart`, `lib/src/device/serial_match.dart`, `lib/src/device/device_identity_registry.dart`, `lib/src/device/ble_connection_lease.dart`, `lib/src/device/ble/ota_ble.dart` |
| Device feature | Bind/search/found/not-found flows, list/detail, carousel, clear, unbind, OTA, BLE debug, and performance diagnostics | `lib/src/features/devices/` |
| Cast feature | Source selection, persistent preview editor, strict device-resolution export, backend conversion, BLE projection, progress/results, recast | `lib/src/features/cast/` |
| Account feature | Email/WeChat auth, registration, password/email/profile maintenance, local email history | `lib/src/features/account/` |
| Gallery feature ("My Album") | Successfully cast photos grouped by device (source: cast records with `deviceUploadState:1`), device filtering, batch recast, and delete (device slot + album record + source cast record). Merged from the former "Device Photos" and "Casting" entries on 2026-08-04 | `lib/src/features/gallery/` |
| Home and Mine | Primary product entry points, selected-device summary, account statistics, navigation cards | `lib/src/features/home/`, `lib/src/features/mine/` |
| Settings and guide | Language, multilingual legal documents including the AI service agreement, version/update, logout/deletion, FAQ pagination and HTML-subset rendering | `lib/src/features/settings/`, `lib/src/features/guide/`, `lib/src/shared/l10n/` |
| AI feature | Sessions, chat history, up to four public image URLs, image compression/upload/enhancement, localized error mapping, and per-user/version consent gating before requests | `lib/src/features/ai/`, `lib/src/network/boltstar_ai_api.dart`, `lib/src/shared/ai_service_consent.dart` |
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
  -> read device core information and require a valid 0x01 six-byte identity
  -> resolve required productId from product model/screen/scan data
  -> BoltFoxApi.addUserProduct(productId, name, canonical full identity)
  -> refresh bound-device list
```

Binding aborts if `productId` cannot be resolved or the complete six-byte identity is unavailable;
it must not send an incomplete backend request. Broadcast short IDs and BLE `remoteId` values must
never be used as binding persistence fallbacks.
The scan-session `remoteId`, user-visible broadcast device ID, editable device name, and protocol
full device ID are different concepts.

### 4. Connecting to an already-bound device

```text
Snapshot the user-selected backend device record
  -> reuse only an active session whose verified full ID and screen type match
  -> otherwise request permission and end any different active session
  -> fast path 1: a frame candidate already held by the system connected-device list
  -> fast path 2: the locally cached remoteId, connected with a short probe timeout
  -> otherwise scan up to the bounded candidate limit
  -> filter by anchored short-ID compatibility and screen type
  -> connect GATT and read command 0x01 full identity
  |    -> match: register verified session and read device state
  `    -> mismatch: disconnect, exclude remoteId, continue scanning
```

Neither fast path carries broadcast manufacturer data, so identity still comes solely from the
0x01 full ID — the same measure the scan path uses. Any fast-path failure must fall back silently
to the full scan without changing failure semantics or error text. Android connect-attempt ladders
are chosen from the candidate's raw RSSI (normal, weak, and a very-weak tier that skips ordinary
`connectGatt` entirely and spends the whole budget on `autoConnect`), and every failed attempt
waits for the disconnect to actually land before retrying. Values and rationale live in
`docs/architecture/BLE_CONNECTION_AND_IDENTITY.md`.

Current code limits same-short-ID verification to four candidates and uses 12-second scan windows.
An editable device name is never identity evidence. Backend records with an old four-byte ID,
all-zero/all-F identity, or invalid format are not compatible records: connecting them must fail
with a rebind instruction.

That identity gate runs before any scan, so the completion chain must run first: the record's own
full ID, then the previous local snapshot, then `DeviceIdentityRegistry`
(`lib/src/device/device_identity_registry.dart`, keyed by backend record id, persisted). A record
that is momentarily missing `deviceId` in one list response is not a device without an identity;
rejecting it there reports a healthy device as "delete and rebind". The registry only ever fills a
gap — it never overrides a fresher backend value, and it only stores complete six-byte IDs.

### 5. Device battery refresh

```text
Connected, fully verified device
  -> show the last valid reading immediately, if one exists
  -> reuse it while younger than 15 seconds
  -> after expiry, issue command 0x04 in the background
  -> merge concurrent refreshes for the same full device ID
  -> valid 0..100 response: update in place
  -> failure/invalid response: retain the old value
  -> no successful reading yet: show `--`
```

Battery display is connected-only. Command `0x01` is not a page-battery source; using both `0x01`
and `0x04` would allow competing values and break the cache contract. A real `0%` is valid and must
not be treated as “missing”.

### 6. Image selection, editing, and projection

```text
Camera/gallery selection
  -> Android gallery uses system Photo Picker without broad media permission
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

### 7. Gallery deletion and device refresh

- The backend gallery response is already user-scoped by `userToken`; state must not re-filter it by
  a concurrently refreshed local owner ID.
- Gallery ordering is newest-first, with numeric `uProductImgId` as a deterministic tie-breaker when
  timestamps are absent/equal.
- Delete (`0x12`) and display refresh (`0x24`) resolve the physical slot through the same logic:
  prefer a valid real `imgIndex` that is occupied in the device mask; only legacy records without an
  index may use constrained inference.
- Slot `0` is valid. Missing/invalid slot is represented by `-1`, never by truthiness.

### 8. BLE/application lifecycle

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

### 9. AI consent and request flow

```text
Enter AI page
  -> AiServiceConsent checks SharedPreferences by agreement version + raw user ID
       accepted    -> continue
       not accepted -> show localized agree/disagree dialog
  -> check bound-device prerequisite
  -> every send/style-generation path checks consent again
       declined -> keep input/pending images and make no AI request
       accepted -> create session when needed -> BoltStarAiApi -> render response

Logout / successful account deletion / session expiry
  -> capture current user ID
  -> remove that user's AI consent key
  -> clear the rest of the session
```

## Important Design Decisions

1. **One shared state and one BLE session.** Pages consume the root-owned `PhotoFrameState` and
   `BleController`; competing page-owned clients would corrupt session identity and callbacks.
2. **Physical identity is always a complete protocol identity.** Backend records, binding,
   deduplication, and active-session ownership require the valid six-byte ID returned by command
   `0x01`. Broadcast short ID and screen type only select candidates; old short-ID backend records
   must be removed and rebound.
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
15. **Android gallery access is selection-scoped.** `main()` globally enables the system Photo
    Picker for `image_picker`. Projection, AI, home-avatar, and profile-avatar flows must not request
    broad photo-library access or reintroduce Android media-read permissions.
16. **Adaptive page skeleton lives in `FigmaScreen`, not per page.** (2026-08-05) The fold/split/
    landscape/large-font contract is: fixed top bar + scrollable content + fixed bottom slot.
    `scrollable: true` (default) covers ordinary pages; `fillViewport: true` covers pages that lay
    themselves out with `Spacer` for one screen (content fills the viewport when short, scrolls when
    tall). Pages whose body already contains an unbounded scrollable keep `scrollable: false` and
    must not enable `fillViewport` (`IntrinsicHeight` cannot measure them). Mirrors the mini-program
    `styles/fold-adapt.wxss`. The home page (`_HomeMainView`, not a `FigmaScreen`) follows the same
    contract by hand: `_HomeTabBar` sits **outside** the scroll area, and its pure-whitespace gaps use
    `_CollapsibleGap` (zero intrinsic height) so a short window shrinks the whitespace first and only
    scrolls once it is fully collapsed — never `Flexible(child: SizedBox(...))`, whose intrinsic height
    makes `IntrinsicHeight` jump straight to scrolling (2026-08-05 home-page regression).
17. **The "My Album" count is cast-success records, not `imgCount`.** (2026-08-05) `minePhotoCount`
    comes from `refreshMineCastSuccessCount()` (all devices, `deviceUploadState: 1`), matching what
    the album list shows. It is stored separately from `castRecords`, whose contents are owned by the
    gallery/cast-management pages' own filters. `UserProfile.imgCount` is still parsed but no longer
    displayed.
18. **AI-service consent is versioned and user-scoped.** `AiServiceConsent` stores acceptance under
    agreement version plus raw login user ID. A missing cache blocks requests, account switching
    never inherits another user's choice, and logout/deletion/session expiry remove the current
    user's key before identity is cleared.

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
   checks, wrong-candidate disconnect, candidate exclusion behavior, and the rejection of
   incomplete backend records.
7. Preserve target-device snapshots through asynchronous business flows.
8. Handle `imgIndex` with explicit numeric comparisons. `0` is a valid slot; unknown is `-1`.
9. Keep BoltFox, seekink, and AI authentication/response handling separate. Do not display AI
   service `detail` directly to users.
10. Keep page battery reads on command `0x04` through `DeviceBatteryCache`. Preserve the 15-second
    TTL, in-flight deduplication, valid `0%`, old-value fallback, and `--` unknown state.
11. User-visible text belongs in `AppL10n`. Engineering-only debug pages may be explicitly exempt.
12. New cast/recast temporary-file prefixes must be registered in `TempCacheSweeper` and documented
    in `docs/architecture/RESOURCE_LIFECYCLE.md`.
13. Do not change BLE pacing, window, MTU/chunk, ACK, connection-interval, or timeout values as a
    cosmetic refactor. Use the iOS performance runbook and real hardware evidence.
14. Restore `BleTuning` defaults after diagnostics; saved experimental values affect ordinary casts.
15. Do not remove Android foreground-service/wake-lock or renderer configuration without verifying
    lifecycle deadlines and affected release devices.
16. Keep Android gallery access on the system Photo Picker. Do not add `READ_MEDIA_IMAGES`,
    `READ_MEDIA_VISUAL_USER_SELECTED`, `READ_EXTERNAL_STORAGE`, or a pre-gallery
    `requestPhotoPermission` gate unless the product gains a real full-library use case and the
    privacy/release decision is revisited.
17. Preserve the AI-service consent gate before session creation, draft clearing, image upload, and
    every BoltStar AI request path. User-visible dialog and agreement text must remain localized.
18. Regular project documentation belongs under `docs/`. `AGENTS.md` and this explicitly requested
    `AI_CONTEXT.md` are root-level AI control/context exceptions.
19. Update the Active owner document when a change alters architecture, API contracts, BLE identity,
    slot semantics, resource lifecycle, cross-client behavior, platform setup, release steps, or
    user-facing multilingual content.
20. Normal validation is:

    ```bash
    dart analyze lib test
    flutter test
    ```

    BLE transfer, connection intervals, OTA, camera/gallery, WeChat login, background behavior, and
    release-only platform configuration require real-device validation.
21. Android debug/profile/release artifacts all use the same release certificate and require complete
    `android/key.properties`; do not add signing secrets to Git. iOS release setup and the WeChat
    Universal Link remain external build inputs.

## Known Risks

- **Critical integration paths have limited automated coverage.** CodeGraph reports no direct tests
  covering `ServerImageProjectionService.castImages`, bound-device connection orchestration,
  `PhotoFrameState.bindDevice`, or the BLE debug/performance pages. Existing tests focus on protocol
  parsing, serial matching, connection leases, API rows, localization/widgets, and auth UI.
- **Same-short-ID devices can cross-connect if identity rules regress.** The full-ID verification and
  wrong-candidate exclusion path is safety-critical.
- **Historical short-ID backend records are intentionally blocked.** They cannot be safely mapped
  to one physical frame. Product/support migration must delete and rebind them; restoring a
  short-ID compatibility path would reintroduce cross-device ownership.
- **The mini-program OTA document currently contradicts both implementations.**
  `photo-album/docs/protocols/ota-dfu.md` disagrees with the current mini-program
  `utils/ota-ble.js` and Flutter `ota_ble.dart` about DATA sequence bytes, the direction of `0xF3`,
  and minimum firmware size. Do not change Flutter OTA from that document until the mini-program
  owner corrects the source-of-truth conflict and real-device behavior is reconfirmed.
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
- 2026-07-28 strict device-identity and `0x04` battery-cache synchronization;
- the July runbook change digest;
- `docs/history/2026-08/` August change records, including 2026-08-04 "My Album" module merge plus
  fold-screen review and 2026-08-05 cast-success count + `FigmaScreen.fillViewport`.

## AI Working Notes

1. Re-run `codegraph status` instead of relying on copied counts; the index changes with source.
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
  `serial_match.dart`, `battery_cache.dart`.
- Projection call path: `CastingProgressPage`, `ServerImageProjectionService.castImages`,
  `CastImageEditor`, transfer information/rollback paths.
- Binding call path: `BindDeviceFlowPage`, `PhotoFrameState.bindDevice`,
  `BoltFoxApi.addUserProduct`.
- Battery call path: page refresh -> `PhotoFrameState.refreshConnectedDeviceInfo` /
  `_refreshDeviceBattery` -> `DeviceBatteryCache` -> `FrameBleClient.readBattery`.

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
