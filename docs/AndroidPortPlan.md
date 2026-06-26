# Brief: Build the ReFx Android app (native, 1:1 with the iOS app)

> Hand this whole document to your build agent. It is the authoritative brief
> for porting the existing **ReFx** iOS app to **native Android**. Read the two
> reference repos before writing code (links in §1). Build for **1:1 feature
> and visual parity** with the iOS app, against the **same backend**.

---

## 1. Mission & reference material

ReFx is a game-server hosting platform (think GPortal/Pterodactyl-style). There
is already a polished **native SwiftUI iOS app** and a **NestJS backend + Next.js
web panel**. Your job: build the **native Android client** with the same feature
set, the same backend, and the same "ReFx Glassy" look.

**Read these first (both are on GitHub, public):**
- `ReFxFrank/ReFxHostingApp` — the **iOS app** (Swift/SwiftUI). This is your
  reference implementation: exact screens, field names, view-model logic,
  networking layer, design tokens, and decode/encode tests. When in doubt about
  behaviour, match what this app does.
- `ReFxFrank/ReFxHosting` — the **backend + web panel** (TypeScript). Source of
  truth for the API. Especially:
  - `docs/03-api.md` (endpoint catalogue), `docs/07-billing.md`,
    `docs/02-database.md`, `docs/08-security.md`, `docs/17-integration-map.md`
  - `apps/panel-api/src/**` (NestJS controllers + DTOs — authoritative request/
    response shapes)
  - `apps/web/lib/api.ts` + `apps/web/lib/types.ts` (the web client's typed API
    surface — a fast way to read every endpoint and payload)

Treat the backend as fixed. **Do not change the API.** If something seems
missing, re-read the panel source before assuming.

---

## 2. Non-negotiables (working agreement)

- **Native Android. Kotlin + Jetpack Compose + Material 3.** No Flutter/RN/KMP.
- **Separate repo and project** from iOS. New Gradle project, own CI, own
  signing, Google Play Console.
- **Architecture:** MVVM. `ViewModel` + `StateFlow`, unidirectional data flow,
  Kotlin coroutines. Navigation-Compose. A repository/"service" per domain over
  a single networking client.
- **Min SDK 26 (Android 8.0), target the latest stable SDK.** Phone + tablet
  (responsive layouts; the iOS app is universal).
- **Match the iOS UX, not pixel-for-pixel chrome.** Use platform-correct Android
  patterns (back button, bottom nav, Material ripples) while reproducing the
  ReFx visual system (§6) and every screen/flow (§5).
- **CI from day one** (GitHub Actions): assemble + unit tests on every push;
  signed bundle + Play upload on release. Mirror the iOS repo's discipline
  (small branches, green CI before merge).
- **No secrets in the repo.** Signing keystore, Play service-account JSON, and
  the Firebase config go in CI secrets / local-only files.

---

## 3. Backend integration

### 3.1 Base URLs & config
- API origin (prod): `https://api.refx.gg`  ·  REST base = origin + `/api/v1`
- Web origin (prod): `https://refx.gg` (used for web link-outs + legal pages)
- Socket origin = API origin; live console namespace path `/ws/console`
- Make origins overridable at runtime from a Settings screen (persist in
  DataStore). These are non-secret origins, never tokens.

### 3.2 Transport & envelope
- All REST is JSON over HTTPS. Use **Retrofit + OkHttp + kotlinx.serialization**
  (or Ktor client — your call; Retrofit recommended).
- **Success envelope:** responses are `{ "success": true, "data": <T> }`. The
  client must **auto-unwrap `data`** so call sites get `<T>` directly. Errors
  come back as `{ "success": false, "error": { "message", "code", ... } }` (and/
  or non-2xx). Model a single `ApiError` with a user-facing `message`.
- **Pagination:** list endpoints return `Page<E> = { items: [E], meta: {...},
  hasMore: Bool }` (sometimes nested under the envelope). Provide a
  `sendPaginated` path returning `items` + `hasMore` for infinite scroll.
- **Dates:** ISO-8601, **with and without fractional seconds**. Configure the
  serializer to accept both (`...Z` and `...,SSSZ`). The iOS app uses a custom
  decoder that tries fractional first, then plain — replicate that tolerance.
- **Auth:** Bearer access token + refresh token. On 401, transparently refresh
  once and retry; on refresh failure, sign out. Store tokens in
  **EncryptedSharedPreferences / Keystore** (the iOS app uses Keychain).
- **Money:** integer **minor units** + ISO currency code. Build a `Money(minor,
  currency)` with a `.formatted` like the iOS one. Never use floats for money.

### 3.3 Enum tolerance (important)
Every server enum is decoded **permissively**: unknown raw values map to a
`.unknown` case instead of throwing, so a backend addition never crashes the
client. Implement this for **all** enums (custom deserializers). Enums include:
`InvoiceState, PaymentState, SubscriptionState, BillingInterval, BillingModel,
ProductType, CreditReason, CouponKind, VariableType, DeployMethod, NodeState,
NodeOS, UserRole, ServerState`, ticket state/priority, alert severity, etc.

### 3.4 Live console
The server console is **Socket.IO** (namespace `/ws/console`), authenticated
with the bearer token. Use `io.socket:socket.io-client` for Android. Stream
output lines; send commands; handle power-state changes. Mirror the iOS
`ConsoleSocket`.

### 3.5 Endpoint inventory (by domain)
Confirm exact shapes against the panel source; this is the map.

**Auth / account**
- `POST auth/login`, refresh, logout; 2FA (TOTP) enroll/verify; WebAuthn/passkey
  (optional for v1 — iOS has it)
- `GET account` (current user + order profile: email-verified, billing address,
  credit balance), `PATCH account`
- Security: API keys (list/create/revoke), active sessions (list/revoke),
  change password
- Push tokens: `POST account/push-tokens { token, platform: "android" }`,
  `DELETE account/push-tokens/{token}`
- Notifications feed + unread count

**Servers (customer)**
- `GET servers` (paginated, `q` search), `GET servers/{id}`
- Power control (start/stop/restart/kill), live console (socket)
- Files (browse/edit/upload, signed download URLs — open in browser),
  Backups (create/restore/lock/delete; signed download), Schedules (cron tasks),
  Databases (create/rotate), Sub-users (grants + per-server permission strings)
- Mods / Modpacks / Workshop (game-conditional), Voice (TeamSpeak admin)
- Switch game, Upgrade/resize (`GET` upgrade options → `POST` plan change with
  proration preview), server Settings (startup vars, reinstall)

**Catalog (public; bearer ignored)**
- `GET catalog/products`, `catalog/templates`, `catalog/locations`,
  `catalog/nodes` (capacity query: `cpuCores,memoryMb,diskMb[,regionId]`)

**Billing (customer)**
- Subscriptions (list; `POST billing/subscriptions/{id}/cancel?atPeriodEnd=`,
  `/resume`), Invoices (list/detail; pay on web), Payment methods (hosted
  add-card — open web, no card entry in app)
- `POST orders` (new-server checkout; returns `{ paid, serverId, checkoutUrl }`)
  — **see compliance §8**, coupon validate, gift-card lookup

**Support**
- Tickets list/create/detail/reply (state + priority enums)

**Staff / Admin** (role + permission gated server-side)
- Overview/metrics: `GET admin/metrics`, `admin/billing/summary`
- Servers: `GET admin/servers` (paginated, search), `DELETE admin/servers/{id}`,
  **`POST admin/servers`** `{ name, ownerId, nodeId, templateId, cpuCores?,
  memoryMb?, diskMb?, slots?, swapMb?, environment? }` (admin direct-provision)
- Nodes: `GET admin/nodes` (paginated), `GET admin/nodes/{id}`, ping,
  restart-agent, update-agent, steam-cache/clear, `agent-latest`,
  **`POST admin/nodes`** `{ name, fqdn, regionId, os, cpuCores, memoryMb, diskMb,
  allocationPortStart, allocationPortEnd }` → returns the node **plus a one-time
  `bootstrapToken`** (show once, copy-to-clipboard, "can't be retrieved" warning)
- Users: `GET admin/users` (paginated, search), `GET admin/users/{id}`,
  `PATCH admin/users/{id}` (state: ACTIVE/SUSPENDED/BANNED),
  `PATCH admin/users/{id}/role`, `POST admin/users/{id}/verify-email`,
  **`POST admin/users/{id}/credit`** `{ amountMinor, reason, note }` (negative to
  deduct)
- Catalog admin: products (+ tiers + prices), templates (eggs), coupons, gift
  cards
- Billing admin: orders (delete), invoices (void / mark-paid / delete), payments
- Platform: roles (+ permission catalogue), locations/regions, settings
  (email / steam / payment gateways — masked secrets), audit logs, alerts
  (banner: create/toggle/delete)

> The iOS `StaffService` + `StaffServiceConfig` files enumerate every admin call
> with its exact path — use them as the checklist.

---

## 4. Data models

Port the model layer 1:1 from the iOS app (`ReFxApp/Models/**`). Notes:
- Reuse the same field names the API uses (camelCase). Default serializer keys,
  no snake_case conversion.
- Make optional anything the iOS struct marks optional; decode permissively
  (ignore unknown JSON keys).
- Shared admin enums live together in iOS `AdminConfigModels.swift` — mirror
  that grouping. Each has the `.unknown` fallback (§3.3).
- Key value types: `Money` (minor units), `Page<E>`, `LoadState<T>` (see §6.4),
  `Server`, `Ticket`, `Invoice`/`InvoicePayment`, `Subscription`, catalog types
  (`CatalogProduct/Tier/Price/Template/TemplateVariable`), admin types
  (`AdminUser/AdminUserDetail`, `NodeAdmin`, `AdminGameTemplate`, `Region`, etc.).

Write **unit tests** that decode representative JSON for each domain and assert
the permissive-`unknown` behaviour — mirror the iOS
`Tests/ReFxAppTests/*DecodingTests.swift` and `AdminProvisioningTests.swift`
(which also assert the exact request-body keys for `POST admin/servers` and
`POST admin/nodes`). These tests are the contract guards; keep them.

---

## 5. Screen / feature inventory (build all; 1:1 with iOS)

Role-aware bottom navigation: **Home, Servers, Support, (Staff), Account.** Staff
tab only for staff roles.

**Auth & shell**
- Launch/auth gate, Login (email+password), 2FA TOTP prompt, App Lock
  (biometric unlock + "sign out" escape), Privacy curtain when backgrounded.

**Home / Dashboard** — glance view: servers needing attention, quick stats.

**Servers**
- List (live status pills, search, attention banner, pull-to-refresh, periodic
  refresh while visible). New-server "+" gated by purchasing flag (§8).
- Detail with sections (game-conditional): Console (live), Files, Backups,
  Schedules, Databases, Power controls, Mods, Modpacks, Workshop, Voice,
  Switch Game, Upgrade/resize, Settings, Sub-users.

**Support** — ticket list, create ticket, thread + reply.

**Billing** (under Account) — subscriptions (cancel/resume), invoices + detail,
payment methods (hosted add-card on web), store credit display.

**Account** — profile header; Security (2FA, API keys), Sessions, Change
password; Notifications (push settings + diagnostics: permission / token /
server-sync rows, copy token, re-register); **About & legal** (Privacy Policy →
`{web}/privacy`, Terms → `{web}/terms`, Help & Support → `{web}/support`, app
version row); Sign out.

**Staff / Admin** — Overview, Queue, Servers (+ create wizard), Nodes (+ add-node
form with bootstrap-token result), Users (+ detail with suspend/ban/verify/role
and **Adjust store credit** sheet), Products (+ detail), Templates, Coupons,
Locations, Roles, Settings (email/steam/gateways), Audit log, Platform alerts.

For each screen, match the iOS view-model: load → `LoadState`, error with retry,
empty state, refresh. The iOS `*View.swift` + `*ViewModel.swift` pairs are the
spec.

---

## 6. Design system — "ReFx Glassy" → Compose

Build a Compose theme + component library that reproduces the iOS one. Read the
tokens/components in `ReFxApp/Core/DesignSystem/**`.

### 6.1 Color tokens (map to Compose `Color` + Material 3 scheme)
Dark, glassy, deep-navy base with a blue primary and accent text. Token names
(define equivalents): `appBackground, appCard, appBorder, appForeground,
appForegroundStrong, appMuted, appLabel, appPrimary, appSecondary,
appAccentText, appSuccess, appWarning, appDestructive`. Pull the exact hex
values from the iOS asset catalog / color definitions.

### 6.2 Components (build Composables)
- `GlassCard` (translucent card w/ border + subtle glow), `cardSurface()`
  modifier, `screenBackground()` (app gradient/sheen)
- `SectionHeader(title, icon, trailing)`, `Eyebrow` (uppercase tracked label)
- `StatCard`, `StatusChip(text,color)`, `StatePill(state)` (server/node state
  → color), `ManageRow`, `RoleBadge`
- Buttons: `refxPrimary`, `refxSecondary`, `refxDestructive` (each with a
  full-width variant) → Compose button styles
- `SkeletonBlock` (shimmer) for loading

### 6.3 Typography & feel
Match weights/sizes/monospaced-digits usage. Use rounded/SF-like system font;
keep the tight, modern, slightly-techy tone. Reproduce haptics on key actions
(`HapticFeedback`).

### 6.4 `LoadState` + `AsyncStateView`
Port the `LoadState<T>` sealed type (`Idle / Loading / Loaded(T) / Failed(error)`)
with a `.value` accessor, and an `AsyncStateView`-equivalent Composable:
`AsyncState(state, isEmpty, emptyTitle, emptyMessage, onRetry, content,
skeleton)`. This wraps nearly every screen — build it first.

---

## 7. Push notifications (APNs → FCM)

- Use **Firebase Cloud Messaging**. Create a Firebase project; add the Android
  app; commit nothing secret (the `google-services.json` is config, not a
  secret, but coordinate with the human).
- On sign-in (and on FCM token refresh), register the token:
  `POST account/push-tokens { token, platform: "android" }`. Unregister on sign
  out. **Re-register after sign-in even on a fresh login** (the iOS app had a
  bug where the token uploaded before auth and was never retried — don't repeat
  it: register on the signed-in transition).
- Notification **types** the backend sends: `server.state`, `billing.invoice`,
  `support.reply`. Payload carries `type` plus an id (`serverId` / `invoiceId` /
  `ticketId`).
- **Deep-linking:** a tapped notification must open the right tab **and** the
  exact entity (server / invoice / ticket). Implement a router that survives
  **cold launch** (intent extras present before the UI exists) — apply the
  pending route once the nav host is ready, not only on a live "changed" signal.
  The iOS app's `PushRouter` + tab-root `navigationDestination` pattern is the
  model; on Android use a `PendingRoute` consumed by the NavHost on first
  composition.
- Foreground display: show a banner/notification; update unread badge on Account.
- The backend's in-app notification feed (modpack/job events) is separate from
  push — keep both.

---

## 8. Store compliance (Google Play)

Mirror the iOS approach. Game-server hosting is a **service consumed outside the
app**, so paying by card is allowed and must **not** be forced through Google
Play Billing (Play policy parallels Apple 3.1.3). To stay clearly compliant:
- Keep a **`purchasingEnabled` feature flag**. Auto-enable on debug/internal
  builds; **auto-disable on production Play builds** so the in-app "buy a new
  server" flow is hidden and purchasing stays on the web. New servers are bought
  on `refx.gg`; the app manages servers the user already owns.
- This keeps the app a **free companion app** for review.
- Fill the Play **Data safety** form to match the iOS App Privacy answers:
  collects email, name, physical (billing) address, and a device push token —
  all for app functionality, **no tracking, no analytics/ads SDKs**. Payment
  card data is **not** collected by the app (entered on web). The only third-
  party SDK is the Socket.IO client (+ Firebase Messaging for push).
- Add in-app **Privacy Policy / Terms** links (Account ▸ About & legal, §5).
- Export compliance: standard TLS only.

---

## 9. Platform specifics (iOS feature → Android equivalent)

- **App lock:** `BiometricPrompt`; fall back to device credential; always offer
  "sign out" so a user can't be locked out.
- **Background refresh / outage checks:** `WorkManager` periodic worker (iOS used
  BGTaskScheduler). Best-effort; respect Doze.
- **Live Activities / Dynamic Island** (server-op progress): no 1:1 Android
  equivalent. For v1 use an **ongoing/foreground notification** with progress for
  long ops, or defer. Don't block parity on this.
- **Widgets:** iOS has a home-screen widget. Optional v1; if built, use **Glance**.
- **Secure storage:** EncryptedSharedPreferences / Keystore (tokens), DataStore
  (non-secret prefs/origins).
- **Web link-outs:** open `https`-only URLs in a Custom Tab (Chrome Custom Tabs);
  never launch arbitrary schemes from server-provided URLs (the iOS `WebLink`
  guards scheme = https only — replicate).
- **Deep links / associated domains:** support `https://refx.gg/...` app links if
  desired (iOS has associated-domains); optional v1.

---

## 10. Project setup & tooling

- **Gradle (Kotlin DSL)**, Compose BOM, Material 3, Navigation-Compose.
- Libraries: Retrofit + OkHttp + kotlinx-serialization (or Ktor); Coil (images);
  DataStore; AndroidX Security (EncryptedSharedPreferences); `socket.io-client`;
  Firebase BoM + Messaging; AndroidX Biometric; WorkManager; (optional) Glance.
- **CI (GitHub Actions):**
  - PR/push: `./gradlew assembleDebug testDebugUnitTest lint` on `ubuntu-latest`.
  - Release: build a signed **AAB**, upload to Play **internal** track via the
    Gradle Play Publisher plugin or fastlane `supply`, using a Play service
    account JSON from secrets. (Parallels the iOS auto-TestFlight-on-main.)
  - Keep keystore + service-account JSON + Firebase secrets in GitHub secrets.
- **Package layout:**
  ```
  core/ (network: ApiClient, envelope, auth interceptor, error; storage; design)
  data/ (models, enums, repositories/services per domain)
  feature/ (servers, billing, support, account, staff, auth — VM + screens)
  app/ (Application, nav graph, theme, push)
  ```

---

## 11. Build order (milestones)

1. **Foundation:** project + theme/design system + `LoadState`/`AsyncState` +
   networking client (envelope, auth/refresh, dates, errors) + secure token
   storage. Login → authenticated shell with bottom nav.
2. **Servers core:** list + detail + power + **live console (socket)**. This
   proves the hardest integration early.
3. **Account + Billing + Support:** account/security/sessions/push-settings/
   about-legal; subscriptions/invoices; tickets. Push notifications end-to-end.
4. **Remaining server sections:** files, backups, schedules, databases, mods/
   modpacks/workshop, voice, switch-game, upgrade, settings, sub-users.
5. **Staff/Admin:** overview, servers (+create), nodes (+add/bootstrap), users
   (+credit), products/templates/coupons/locations/roles/settings/audit/alerts.
6. **Compliance + polish:** purchasing gate, Data safety, store listing,
   screenshots, hardening tests, accessibility, empty/error states.

Ship each milestone behind green CI. Keep parity with the iOS app as the
acceptance bar for every screen.

---

## 12. What to get from the human before/while building

- Confirm prod origins (`https://api.refx.gg`, `https://refx.gg`) and any
  staging origin for testing.
- A **test customer account** (with a server, invoice, ticket; 2FA off) and a
  **staff account** for the admin screens.
- **Firebase project** access (to add the Android app + get `google-services.json`)
  and confirmation the backend can send FCM (it already sends APNs; the push
  module likely needs an FCM sender key configured — coordinate).
- **Google Play Console** access, an app entry, and a signing keystore (or use
  Play App Signing) + a Play service-account JSON for CI uploads.
- App icon / brand assets (or extract/redraw from the iOS asset catalogue).
- Legal URLs are `{web}/privacy`, `{web}/terms`, `{web}/support` (confirmed).

---

### Definition of done
Every screen in §5 implemented and matching the iOS app's behaviour and look;
all domains wired to the real backend with permissive decoding; push deep-links
working incl. cold launch; purchasing gate correct for Play; Data safety + store
listing ready; CI green with the contract unit tests passing; a signed AAB on
the Play internal track.
