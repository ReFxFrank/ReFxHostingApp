# ReFx Companion App (iOS) — Security Review

**Date:** 2026-06-25
**Scope:** `ReFxApp/` (app), `ReFxWidget/` (widget extension), `Shared/`, build config (`Info.plist`, entitlements, `Config/*.xcconfig`), and CI signing workflow.
**Standard:** OWASP MASVS / MASTG.
**Branch:** `security/audit-2026-06-25` (local; not pushed — per protocol).

---

## 1. Executive summary

Overall posture is **good**. The app is built like a client that knows it is *not* the security boundary: authentication tokens live only in the Keychain (`AfterFirstUnlockThisDeviceOnly` — never `UserDefaults`/plist/file, never synced to iCloud or backups), TLS validation is intact (no custom `URLSessionDelegate` weakening it, ATS enforced), the refresh flow is a single-flight actor that handles rotation, billing opens in the system browser (no in-app WebView the app can read), the live console renders to native `Text` (no HTML/WebView injection sink), there is **no logging at all**, and the widget/app-group container holds only non-sensitive aggregate counts.

The audit found **no Critical or High issues** — no remote credential theft, no broken TLS validation, no trivial auth bypass, no in-app RCE. Findings cluster in the **Medium/Low hardening** band and are dominated by on-device / device-compromise attacker models.

**Counts by severity (16 findings):**

| Severity | Count | Fixed/Mitigated | Flagged |
|---|---|---|---|
| Critical | 0 | – | – |
| High | 0 | – | – |
| Medium | 3 | 3 | 0 |
| Low | 9 | 5 | 4 |
| Info | 4 | 1 | 3 |

**Top risks (plain language):**
1. **Secrets on the clipboard** — DB passwords, API keys and the TOTP setup secret were copied to the system-wide pasteboard with no expiry, where other apps or a paired Mac could read them. *(Fixed.)*
2. **App-switcher snapshot** — the console, server IPs and revealed secrets were captured in the task-switcher thumbnail on backgrounding. *(Fixed.)*
3. **App-lock didn't re-engage** — the Face ID lock only ran on cold start, so backgrounding and returning resumed a privileged session with no re-auth. *(Fixed.)*

Everything fixable with a clear, low-risk change was fixed (8 commits). The remaining items are architectural/operational and are **flagged with concrete recommendations** rather than changed blindly: certificate pinning, binding the app-lock to a Keychain access-control item, a cross-instance refresh-token race, and supply-chain pinning / a hardcoded CI passphrase.

---

## 2. Scope & methodology

**Reviewed (mapped to MASVS):**
- **MASVS-STORAGE** — `KeychainService`, `AuthStore`, `AppConfig`, the app-group `WidgetStore`/`ServerSnapshot`, pasteboard use, backgrounding/snapshot, `URLCache`.
- **MASVS-CRYPTO** — randomness & key handling (passkey/WebAuthn uses the platform `ASAuthorization` APIs; no hand-rolled crypto, no hardcoded keys found).
- **MASVS-NETWORK** — ATS config, every `URLSession`/TLS path, the Socket.IO transport, origin configuration.
- **MASVS-AUTH** — refresh-rotation single-flight, biometric app-lock, MFA/passkey challenge flow, logout/revocation, background re-auth.
- **MASVS-PLATFORM** — URL scheme/associated domains, WebView usage, link-outs, local notifications, Live Activity/widget IPC, entitlement breadth.
- **MASVS-CODE** — Codable/decoding robustness, force-unwraps, path handling in the Files feature, logging, debug code/endpoints.
- **Secrets & supply chain** — repo-wide secret scan, SPM/transitive pins, CI signing material.

**Method:** direct source + config reading to confirm exploitability; a fan-out review across the six MASVS dimensions with an **adversarial verification pass** (each finding re-checked against the real code to refute it / recalibrate severity) and a completeness critic. 23 review/verify passes; one candidate finding was rejected as a false positive (see §6).

**Attacker models used:** (a) remote / network MITM, (b) on-device malware (another installed app), (c) attacker holding an unlocked/handed-over device, (d) jailbroken device + physical access. Findings that require (c)+(d) are not rated above Medium.

**Not covered / out of scope:** server-side authorization (the app correctly treats the server as the boundary), the backend API itself, runtime/dynamic analysis on a device, and a MobSF scan of a built `.ipa` (no build artifact produced in this environment — see §7 Limitations).

---

## 3. Findings summary

| ID | Title | Severity | Status | Commit |
|---|---|---|---|---|
| STOR-1 | Secrets copied to global pasteboard (no expiry/local-only) | Medium | Fixed | `dea5ed8` |
| STOR-2 | No app-switcher privacy overlay (snapshot leak) | Medium | Fixed | `2be7924` |
| AUTH-2 | App-lock doesn't re-engage on return from background | Medium | Fixed | `5c34077` |
| STOR-3 | Authenticated responses in default on-disk `URLCache` | Low | Fixed | `f1b611a` |
| NET-1 | No certificate/public-key pinning (API + Socket.IO) | Low | Flagged | – |
| NET-2 | Persisted origin override → traffic-redirect vector | Low | Mitigated | `b633fd6` |
| AUTH-1 | Biometric app-lock fails **open** on eval failure | Low | Fixed | `98b6ca9` |
| AUTH-3 | App-lock not bound to a Keychain access-control item | Low | Flagged | – |
| CODE-1 | `WebLink.open` opens server-controlled URL, no scheme check | Low | Fixed | `37a167e` |
| SUP-1 | No committed `Package.resolved`; floating `from:` pin | Low | Flagged | – |
| SUP-2 | Distribution `.p12` passphrase hardcoded in CI | Low | Flagged | – |
| AUTH-4 | Per-instance refresh single-flight → cross-instance double-spend | Low | Needs-verification | – |
| NET-3 | localhost cleartext ATS exception ships in release | Info | Mitigated | `edf16e6` |
| PLAT-1 | Server name/state on lock screen (no secrets) | Info | Won't-fix | – |
| PLAT-2 | Custom URL scheme declared but unhandled | Info | Won't-fix | – |
| SUP-3 | Provisioning profiles committed to repo | Info | Won't-fix | – |

---

## 4. Per-finding detail

### STOR-1 — Secrets copied to the global pasteboard — **Medium — Fixed**
**Location:** `DatabasesView.swift:86`, `SecurityView.swift:122`, `SecurityView.swift:164` · **MASVS-STORAGE-2 / CWE-200**
The "Copy" actions for a revealed **database password**, a freshly-created **API key** (a long-lived scoped bearer credential), and the **TOTP setup secret** wrote the value to `UIPasteboard.general.string` with no `expirationDate` or `.localOnly`. That value is readable by other apps while present, mirrored to the user's other Apple devices via Universal Clipboard, and never expires.
**Impact:** clipboard disclosure of high-value secrets; a leaked TOTP secret permanently defeats the second factor.
**Attacker model:** on-device malware / the user's own Handoff-paired devices.
**Remediation (applied):** added `Clipboard.copySecret()` (`Core/Security/Clipboard.swift`) using `setItems(_:options:)` with `.localOnly: true` and a 60-second `.expirationDate`; routed the three secret copies through it. The non-secret IP chip is left as a normal copy intentionally.

### STOR-2 — App-switcher snapshot leak — **Medium — Fixed**
**Location:** `App/ReFxAppApp.swift:33` · **MASVS-STORAGE-2 / MASTG-TEST-0014 / CWE-200**
The `scenePhase` handler never covered the UI when leaving the foreground, so iOS's task-switcher snapshot captured whatever was on screen — live console output, server `IP:port`, and one-time-revealed secrets.
**Impact:** someone with brief access to the unlocked/handed-over device can read sensitive content from the app-switcher thumbnail.
**Attacker model:** unlocked device / shoulder-surf.
**Remediation (applied):** an opaque branded `PrivacyCurtain` overlay is shown whenever `scenePhase != .active`, so the snapshot shows only the curtain.

### AUTH-2 — App-lock doesn't re-engage on background — **Medium — Fixed**
**Location:** `Core/Auth/AppSession.swift:130`, `App/ReFxAppApp.swift:33` · **MASVS-AUTH / CWE-613**
The Face ID app-lock ran only on cold start. Backgrounding a signed-in session and returning resumed straight into content, so the lock gave no protection during normal app switching.
**Impact:** an attacker with the unlocked device resumes a privileged session despite the lock being enabled.
**Attacker model:** unlocked device.
**Remediation (applied):** `lockForBackground()` sets `phase = .locked` on `scenePhase == .background` when the lock is enabled; returning to the app re-prompts Face ID. A **Sign out** escape was added to the lock screen so a user can never be hard-locked-out.

### STOR-3 — Authenticated responses in the on-disk URL cache — **Low — Fixed**
**Location:** `Core/Networking/APIClient.swift:20` · **MASVS-STORAGE-1 / CWE-524**
`URLSession.shared`'s default `URLCache` can persist authenticated JSON to the app container on disk.
**Impact:** sensitive responses readable with filesystem access (jailbreak / backup at rest).
**Attacker model:** jailbroken+physical / backup extraction.
**Remediation (applied):** the API client now defaults to an **ephemeral** `URLSession` (in-memory cache, no persisted cookies/credentials, `reloadIgnoringLocalCacheData`). The injectable `session` parameter is preserved for tests.

### NET-1 — No certificate/public-key pinning — **Low — Flagged**
**Location:** `Core/Networking/APIClient.swift`, `Core/Realtime/ConsoleSocket.swift:101` · **MASVS-NETWORK-1 / CWE-295**
TLS validation is correct (system default, never weakened) but there is **no SPKI pinning**, so any CA-trusted certificate — including a user/MDM-installed root or a coerced/rogue CA — is accepted on the token-bearing channels.
**Impact:** MITM of the API + Socket.IO channels if the attacker can present a trusted certificate. Requires defeating standard TLS first, so not Critical/High for a clean device.
**Attacker model:** network MITM holding a trusted cert.
**Recommendation:** add SPKI pinning for the API + Socket.IO origins with **backup pins** and a documented rotation process; on mismatch call `completionHandler(.cancelAuthenticationChallenge, nil)` (never `.useCredential` unconditionally). For Starscream, supply a `CertificatePinning`/SSL settings object. **Flagged** rather than implemented: pinning a privileged control app wrong (no backup pin, no rotation plan) risks bricking the app on certificate renewal — it needs ops sign-off.

### NET-2 — Persisted origin override redirect vector — **Low — Mitigated**
**Location:** `Core/Storage/AppConfig.swift:67` · **MASVS-NETWORK / CWE-15**
`AppConfig` read an API/Web origin override from `UserDefaults`. The in-app UI to set it was removed, but the read remained — a dormant redirect vector for anyone able to write the app's sandboxed `UserDefaults`.
**Impact:** sandbox write (jailbreak / tampered backup) could repoint all REST + Socket.IO traffic (with the Bearer token) to an attacker host.
**Attacker model:** jailbroken / tampered-backup.
**Remediation (applied):** the override read is gated behind `#if DEBUG`. Release always uses the baked-in `Info.plist` origin / fallback; DEBUG retains it for local development. Combine with NET-1 for full defense.

### AUTH-1 — Biometric app-lock fails open — **Low — Fixed**
**Location:** `Core/Auth/AppLock.swift:35` · **MASVS-AUTH / CWE-636**
`authenticate()` returned `true` (unlocked) when `canEvaluatePolicy` was false.
**Impact:** an attacker who could render biometrics/passcode unevaluable would bypass the (soft) lock. Low because the lock is content-hiding only; tokens are separately Keychain-protected.
**Attacker model:** jailbroken/instrumented device.
**Remediation (applied):** fail **closed** (return `false`) on evaluation failure — safe now that the lock screen has the Sign-out escape from AUTH-2.

### AUTH-3 — App-lock not bound to a Keychain access-control item — **Low — Flagged**
**Location:** `Core/Auth/AppLock.swift:28`, `Core/Storage/KeychainService.swift:43` · **MASVS-AUTH / CWE-287**
The biometric lock is a SwiftUI phase gate; the refresh token is stored `AfterFirstUnlockThisDeviceOnly` **without** `SecAccessControl` biometry binding. On an instrumented device the gate is bypassable and the token is still readable. The code documents this as privacy-only, not a boundary.
**Recommendation:** if a real boundary is wanted, store the refresh token under `SecAccessControl(.biometryCurrentSet`/`.userPresence)` and pass an `LAContext` on read so token access requires a fresh biometric assertion. **Flagged** — this changes token storage and risks lockout on biometric enrolment changes; needs a re-enrol/relogin UX.

### CODE-1 — `WebLink.open` lacks scheme validation — **Low — Fixed**
**Location:** `Core/Networking/WebLink.swift:6`, `Files/FilesService.swift:43` · **MASVS-PLATFORM / CWE-939**
Server-controlled signed download URLs were handed straight to `UIApplication.shared.open`; a malicious/compromised backend could return a non-web scheme to launch another app.
**Remediation (applied):** validate the resolved scheme is `https` (allow `http` only in DEBUG) before opening.

### SUP-1 — No committed lockfile; floating SPM pin — **Low — Flagged**
**Location:** `project.yml:13`, `.gitignore:9` · **CWE-1104**
`SocketIO` (which transitively pulls **Starscream**) is pinned `from: 16.1.0`, and `Package.resolved` is gitignored, so the exact resolved versions of this privileged build are neither locked nor reviewed.
**Recommendation:** pin `SocketIO` to an exact tag in `project.yml`, commit a resolved lockfile via a CI step (XcodeGen regenerates the `.xcodeproj`, so the resolved file needs an explicit capture), add dependency review to CI, and confirm the resolved Starscream version against advisories. **Flagged** — changing pins without a resolve/build to verify could break the build.

### SUP-2 — Distribution `.p12` passphrase hardcoded in CI — **Low — Flagged**
**Location:** `.github/workflows/testflight.yml:38` · **CWE-798**
`P12_PASSWORD: refxci` is committed. It protects the distribution `.p12`, which itself is a GitHub **secret** (not in the repo), so the passphrase alone cannot sign — but it is public in git history.
**Recommendation:** move the passphrase to a GitHub Actions secret and **rotate** the distribution certificate/passphrase (the current value is effectively public; deleting from `HEAD` does not purge history). Not changed here to avoid breaking CI (the secret would need to be created first).

### AUTH-4 — Cross-instance refresh-token double-spend — **Low — Needs-verification**
**Location:** `Core/Auth/AuthStore.swift:81`, `Core/Background/BackgroundRefreshScheduler.swift:55` · **MASVS-AUTH / CWE-362**
`AuthStore`'s single-flight refresh is per-instance. The `BGAppRefreshTask` builds its **own** `AuthStore`, so a background refresh and a foreground refresh can both POST `/auth/refresh` with the same rotating token; the reused token can trip server-side family-reuse revocation.
**Impact:** rare spurious full logout (re-auth required). Not a credential-theft vector; likelihood low because BG tasks run while backgrounded.
**Recommendation:** share a single `AuthStore`/single-flight across foreground + background, or coordinate refresh via a process-wide mutex keyed on the token and re-read the token from the Keychain after a refresh. **Flagged** — touches the rotation flow; verify against the backend's reuse policy before changing.

### NET-3 — localhost cleartext ATS exception in release — **Info — Mitigated**
**Location:** `ReFxApp/Resources/Info.plist:97` · **CWE-319**
An ATS exception permits cleartext `http` to `localhost` in all builds (previously including subdomains). Loopback-only, not remotely exploitable.
**Remediation (applied):** removed `NSIncludesSubdomains`. Consider a Debug-only `Info.plist` to drop the exception from release entirely.

### PLAT-1 — Server name/state on the lock screen — **Info — Won't-fix (accepted)**
**Location:** `Core/Background/LocalNotifications.swift:23`, `Shared/ServerOpAttributes.swift:19`
Outage notifications and the Live Activity show server name + state on the lock screen. **No secrets (IPs, tokens) are exposed** — verified the notification body is only `"<name> is now <state>"`. Accepted as intended UX; optionally use generic titles if server names are considered sensitive.

### PLAT-2 — Custom URL scheme declared but unhandled — **Info — Won't-fix**
**Location:** `ReFxApp/Resources/Info.plist:32`
`refxapp://` is registered for the widget deep link, but the app has **no** `onOpenURL`/open-URL handler, so there is no action path to abuse. If routing is added later, validate host/path, require in-app confirmation for any action, and prefer universal links.

### SUP-3 — Provisioning profiles committed — **Info — Won't-fix**
**Location:** `ci/ReFx_AppStore.mobileprovision`
Committed for the Mac-free CI pipeline. A profile contains team/app id + entitlements but **no private key** — not a vulnerability. Optionally generate at CI time via the App Store Connect API the workflow already authenticates with.

---

## 5. Fixed vs. flagged

**Fixed / Mitigated (9):** STOR-1, STOR-2, AUTH-2, STOR-3, NET-2, AUTH-1, CODE-1, NET-3 (and the false-positive review of the console decode path confirmed it is safe).

**Flagged for follow-up (7):**
- **NET-1** Certificate pinning *(highest-value next step for a privileged control app)*.
- **AUTH-3** Keychain-bound biometric boundary.
- **AUTH-4** Cross-instance refresh single-flight.
- **SUP-1** Lockfile + exact dependency pin.
- **SUP-2** Rotate + secret the CI `.p12` passphrase.
- **PLAT-1 / SUP-3** accepted (no action).

### Prioritized next steps
1. **Rotate** the distribution certificate/passphrase and move `P12_PASSWORD` to a secret (SUP-2) — operational, do first.
2. **Certificate pinning** for API + Socket.IO with backup pins + rotation runbook (NET-1).
3. **Consolidate the refresh single-flight** across foreground/background (AUTH-4).
4. **Pin dependencies + commit a lockfile** and add CI dependency review (SUP-1).
5. Decide whether the app-lock should be a real boundary; if so, **bind the refresh token to biometrics** (AUTH-3).

---

## 6. Limitations & false positives

- **Build/test verification:** this review ran in a Linux environment without Xcode/the iOS SDK, so `xcodebuild build`/`test` and a MobSF scan of a built `.ipa` could **not** be run here. The fixes are small, idiomatic, behavior-preserving changes reviewed for compile-correctness; they should be validated by the project's macOS CI (which compiles + runs the unit tests) before release. The branch was intentionally **not pushed** (per protocol) — push to trigger CI when ready.
- **Rejected false positive (CODE-2):** an initial "stats frames silently dropped on malformed input" note was **dropped** — verification confirmed the Socket.IO `console`/`stats`/`power` handlers use safe optional casts + `try?` decoding and a 2000-line buffer cap (`ConsoleSocket.swift:153–206`), and the console renders to native `Text` (`ConsoleView.swift`, no WebView). This is a correctly-implemented control, not a vulnerability.
- **Not exhaustively dynamic:** no on-device runtime/jailbreak testing, no traffic interception was performed; transport findings are from static review of the TLS/ATS/socket configuration.
- Severities are calibrated to the stated attacker models; backend authorization is assumed correct and was not tested.

---

## 7. Positive observations (controls verified correct)

- Tokens **only** in the Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — no `UserDefaults`/plist/file storage, no iCloud-Keychain sync, not migrated to new devices or backups (`KeychainService.swift`).
- **No disabled TLS validation** anywhere — no custom `URLSessionDelegate`/`serverTrust` handling, ATS `NSAllowsArbitraryLoads=false` (`Info.plist`, `APIClient.swift`).
- **Single-flight** refresh serialized in an `actor`; forced re-auth (token clear) on refresh failure (`AuthStore.swift`).
- Billing/link-outs open in the **system browser**, not an in-app WebView; **no `WKWebView` in the app** → no native-bridge/injection sink. The console is native `Text`.
- **No logging** (`print`/`NSLog`/`os_log`) and **no `try!`/`as!`/`fatalError`** in app code → no sensitive-log leakage, no decode-crash DoS.
- The **app-group/widget** container holds only counts + worst-state + timestamp — **no tokens, IPs or secrets** (`ServerSnapshot.swift`, `WidgetBridge.swift`).
- The widget has **no Keychain/token access**; entitlements are tightly scoped (app group + `webcredentials:refx.gg` only).
- File paths are sent to the **server** for validation; **no local filesystem writes** → no client-side path traversal.
