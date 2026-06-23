# ReFx Hosting — iOS Companion App

A native iOS (SwiftUI) **remote server manager** for [ReFx Hosting](https://github.com/ReFxFrank/ReFxHosting).
One role-adaptive app: customers monitor and operate their servers (power, live
console, live stats); staff (SUPPORT/ADMIN/OWNER) additionally get a Staff
section. It is a **companion to the web panel, not a replacement** — purchasing,
paying invoices and signup stay on the web.

> Backend lives in a **separate** repo: `ReFxFrank/ReFxHosting` (`apps/panel-api`,
> NestJS). This repo is the iOS client only. The app never modifies the backend.

---

## Status

**Phase 1 (MVP) — implemented.**

- Configurable API/Web base URLs (build-time `.xcconfig` default + runtime override).
- Auth: email + password, **TOTP / recovery-code MFA**, logout, Keychain token
  storage, **single-flight auto-refresh** on 401 (refresh rotation-safe).
- Optional **Face ID app-lock**.
- **Servers home**: live state pills, key resource, loud treatment of
  down/suspended/crashed servers, pull-to-refresh, pagination, search.
- **Server detail**: permission-aware **power controls** (start/restart/stop/kill,
  destructive ones confirmed, debounced, optimistic state reconciled with socket
  truth), **live console** (Socket.IO stream + command input, reconnect, capped
  buffer, scroll-lock), **live monitor** (CPU/RAM/disk gauges, players/uptime,
  IP:port copy chip).
- **Account**: profile, change password, sessions list + revoke, notifications +
  unread badge.
- **Awareness**: `BGAppRefreshTask` + local notifications on server outage /
  ticket activity (best-effort; see *Awareness* below).
- Unit tests for the auth/refresh state machine and cents formatting.

Phase 2 (files, backups, reinstall/game-switch, sub-users, schedules, widget,
TOTP enroll, API keys) and Phase 3 (staff queue, server/node/user admin, Live
Activity, passkey login) are scaffolded as stubs where surfaced in the tab tree.

---

## Requirements & setup

- **Xcode 15+**, **iOS 16.0+**, Swift 5.9.
- Project is generated with [**XcodeGen**](https://github.com/yonyz/XcodeGen)
  from `project.yml` (no checked-in `.xcodeproj` — keeps diffs reviewable).

```bash
brew install xcodegen      # once
xcodegen generate          # produces ReFxApp.xcodeproj
open ReFxApp.xcodeproj
```

Dependencies are resolved by SPM on first build:
- [`socket.io-client-swift`](https://github.com/socketio/socket.io-client-swift) (live console).

Pick a scheme and run:
- **ReFxApp (Debug)** → points at `http://localhost:4000` (local panel-api).
- **ReFxApp (Release)** → points at the prod HTTPS origin.

### Point it at a local panel-api

```bash
# in the ReFxHosting backend repo
docker compose -f infra/docker/docker-compose.yml up -d
# API on :4000, Swagger at http://localhost:4000/docs
```

- **Simulator** reaches `localhost:4000` directly (Debug default).
- A **physical device** can't see `localhost` — change `API_HOST` in
  `Config/Debug.xcconfig` to your Mac's LAN IP (e.g. `192.168.1.20:4000`), or
  override at runtime in **Account → Connection settings**.

ATS is fully on; Debug relaxes cleartext **for `localhost` only** so the local
HTTP panel works in the simulator. Release is HTTPS-only.

### Configuration

`Config/Base.xcconfig` + `Debug.xcconfig` / `Release.xcconfig` define the
default API/Web origins, injected into `Info.plist` and read by `AppConfig`.
Users can override both at runtime (persisted to `UserDefaults` — origins only,
never tokens).

---

## Architecture

MVVM with a typed service layer; `async/await` + `actor` throughout; no Combine
for networking. See `ReFxApp/`:

| Layer | What |
|---|---|
| `Core/Networking` | `APIClient` (actor): envelope decode, auth header, **401→single-flight-refresh→retry**, error mapping |
| `Core/Auth` | `AuthStore` (actor): token lifecycle + single-flight refresh; `AppSession` (`@MainActor`) coordinator; `AppLock`; `Permission` constants |
| `Core/Realtime` | `ConsoleSocket`: Socket.IO `/ws/console` wrapper (subscribe/stream/command, reconnect, token-aware re-auth) |
| `Core/Background` | `BGAppRefreshTask` scheduler + local notifications |
| `Core/Storage` | `KeychainService` (tokens), `AppConfig` (base URLs) |
| `Core/DesignSystem` | dark control-panel theme (HSL tokens from the web panel), state pill, gauge, terminal, async-state container |
| `Models` | Codable mirrors of panel-api DTOs; cents-aware `Money` |
| `Features/*` | Auth, Servers, Account, Support (stub), Staff (stub) |

The whole graph hangs off `AppSession`, injected as an `@EnvironmentObject`.

### Notable design points

- **Single-flight refresh.** Because refresh rotates (reusing a refresh token
  revokes the session family), all concurrent 401s funnel through one actor and
  await a single `/auth/refresh`. Tested in `AuthRefreshTests`.
- **Response envelope.** panel-api wraps success as `{ success, data }` (and
  paginated as `{ success, data, meta }`). `APIClient` unwraps `.data`.
- **Money is integer minor units (cents) + ISO code, never float.** Formatting
  respects per-currency minor-unit exponents. Tested in `MoneyTests`.
- **Optimistic + reconciled state.** A power tap shows a transitional state
  immediately; the socket `power` frame is the source of truth that supersedes it.

---

## Awareness / notifications (no server push in v1)

Foreground: polls server states + unread count on launch/foreground and
pull-to-refresh; badges the Account tab.

Background: a `BGAppRefreshTask` periodically wakes the app, diffs server states
against the last-known snapshot, and fires **local** notifications when a server
transitions to `OFFLINE`/`SUSPENDED`/`CRASHED` or unread activity rises.

**This is best-effort and not real-time** — iOS decides if/when the task runs.
The code says so. The notification layer is isolated (`Core/Background`) so an
APNs-driven path can replace the poll later without touching feature code.

---

## Backend TODOs (gaps flagged, not worked around)

These need backend work for the corresponding app feature to be fully real-time
or complete. The app does **not** patch around them.

1. **APNs server push.** The backend has in-app notifications but no device-token
   registration or send-on-event. Until then, instant alerts aren't possible —
   v1 uses `BGAppRefreshTask` + local notifications. Needs:
   `POST /account/devices` (register APNs token) + send-on-event in
   `NotificationsService`.
2. **Per-server permissions in the server payload.** `GET /servers/:id` doesn't
   include the *caller's* effective per-server permission set, so the app can't
   precisely hide controls for a restricted sub-user (it relies on the API's
   defensive 403 instead). A `permissions: string[]` field on the server detail
   (like `/auth/me` does for admin perms) would let the UI gate exactly.
3. **Disk total in stats.** The socket `stats` frame and `LiveStats` expose
   `memTotalMb` but disk has no total; the app derives the disk ceiling from the
   server's `diskMb` plan limit. A `diskTotalMb` in the stats frame would be more
   accurate.

---

## API contract (confirmed against controllers + DTOs)

Verified by reading `apps/panel-api/src/{auth,servers,agent,stats,account}` in
`ReFxFrank/ReFxHosting`. Discrepancies vs. the original brief are noted.

### Auth
- `POST /auth/login` `{ email, password, totp?, rememberMe? }` →
  `{ accessToken, refreshToken, expiresIn, mfaRequired?, mfaToken?, methods? }`.
  When MFA is required, tokens are empty and `mfaRequired:true` + `mfaToken` +
  `methods:('totp'|'recovery'|'webauthn')[]` are returned. A correct `totp` can
  be supplied inline on login.
- `POST /auth/mfa/verify` `{ mfaToken, code, method?: 'totp'|'recovery' }` →
  token response. *(Public route.)*
- `POST /auth/refresh` `{ refreshToken }` → rotated token response.
- `POST /auth/logout` `{ refreshToken }` → 204.
- `GET /auth/me` → user profile **plus `permissions: string[]`** (effective admin
  perms). JWT access claims: `{ sub, email, role, type:'access' }`; `role` is the
  `GlobalRole` (`CUSTOMER`/`SUPPORT`/`ADMIN`/`OWNER`).

### Servers
- `GET /servers?page&pageSize&q` → `{ data: Server[], meta }`. Each server
  includes `template`, `node{name,fqdn}`, `allocations`, and a derived
  **`primaryAllocation`**.
- `GET /servers/:id` → one `Server` (+ `variables`).
- `POST /servers/:id/power` — body is **`{ signal }`** where signal ∈
  `start|stop|restart|kill`. The brief said `{ action }`; the real DTO is
  `{ signal }`. Permission `control.power`.
- `POST /servers/:id/command` `{ command }` (REST fallback; socket preferred).
- `GET /servers/:id/stats` → `LiveStats { state, cpuPct, memUsedMb, memTotalMb,
  diskUsedMb, netRxBytes, netTxBytes, players?, uptimeMs? }`.

### Socket.IO — namespace `/ws/console`
- Handshake auth: `{ token: <accessToken> }` (also accepts `Authorization:
  Bearer`). Bad token → `error {message:"unauthorized"}` + disconnect.
- `emit("subscribe", { serverId })` → `subscribed {serverId}` or
  `error {message:"forbidden"}`.
- `emit("command", { command })` — gated on **`control.console`** at the socket
  (the REST `/command` route uses `console.command`).
- Inbound frames:
  - `console` → `{ type:"console", line, stream:"stdout"|"stderr", at? }`
  - `stats` → `{ serverId, cpuPct, memUsedMb, diskUsedMb, netRxBytes,
    netTxBytes, state?, players? }` (raw `StatSample`; **no `memTotalMb`**, unlike
    the REST `LiveStats`)
  - `power` → `{ type:"power", state }`

### Discrepancies vs. the brief
1. **Power body** is `{ signal }`, not `{ action }`.
2. **`ServerState`** has more states than listed: also `CRASHED`,
   `TRANSFERRING`, `PENDING_PAYMENT`. Background outage notifications fire on
   `CRASHED`/`SUSPENDED` (the backend only auto-notifies owners on those two);
   the app additionally treats `OFFLINE`/`PENDING_PAYMENT` as "needs attention".
3. **Socket command permission** is `control.console`, not `console.command`.
4. **Stats shape differs by transport**: REST `LiveStats` has `memTotalMb`; the
   socket `stats` frame does not (it carries `serverId`).
5. All REST success bodies are wrapped in `{ success, data }`; errors are
   `{ statusCode, error, message, path, timestamp }` where `message` may be a
   string or an array (validation).

---

## Tests

```bash
xcodegen generate
xcodebuild test -scheme "ReFxApp (Debug)" -destination 'platform=iOS Simulator,name=iPhone 15'
```

- `AuthRefreshTests` — login, MFA challenge, **single-flight refresh** (20
  concurrent 401s → exactly one refresh call), rotation, failure → session clear.
- `MoneyTests` — cents formatting across 2-/0-/3-decimal currencies.

> Note: this project targets iOS/SwiftUI and must be built with Xcode on macOS;
> it does not compile under a Linux Swift toolchain (no UIKit/SwiftUI there).

---

## Out of scope (by decision)

No in-app purchase / payment / card entry / checkout (link out to web). No APNs
push in v1. No backend modifications. No invented API fields — everything is
verified against the controllers/DTOs and Swagger.
