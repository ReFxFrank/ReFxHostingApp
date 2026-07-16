# Panel ↔ iOS App — Parity Gaps

Tracking checklist of panel features not yet in the native app, from diffing
`docs/…panel feature inventory` against the app's actual endpoint calls
(2026-07). Check items off as they ship. Grouped by planned release.

Legend: ✅ present · ⬜ missing · 🟡 partial

---

## Already covered (for reference)
Servers: power, live console (+ backlog replay + seq), command, reinstall, stats,
files (list/read/write/delete/rename/mkdir/download), backups (create/restore/
download/delete), databases (create/delete/rotate), schedules (list/create-single/
run/delete/enable), Minecraft version/loader, mods, modpacks, workshop (add/toggle/
remove/apply), voice (status/rename/accept-license), switch-game, upgrade/resize,
sub-users, startup, variables, pay. Account: view profile, 2FA/TOTP, API keys,
sessions, change password, notifications, push tokens, export, delete, passkey
**login**. Billing: invoices, pay, subscriptions, payment methods, credit, coupons,
gift cards, new-server checkout. Support: tickets. Staff: servers, nodes (+single
agent update/restart/steam-cache/ping), users, products, templates, locations,
coupons, gift-cards, roles, invoices, orders, payments, billing summary, metrics,
audit, alerts, email/steam settings.

---

## 1.1 — highest customer value
- [x] **File upload** — `POST /servers/:id/files/upload?path=` raw bytes (≤32 MiB; else SFTP). File importer + upload toolbar button.
- [x] **File compress / decompress** — `POST .../compress {paths}→{path}`, `POST .../decompress {path}`. Swipe + context menu.
- [x] **SFTP details + rotate** — `GET /servers/:id/sftp` → {host,port,username}; `POST .../sftp/rotate` → {password} (rotate-to-reveal). `SftpDetailsView`.
- [x] **Multi-task schedules** — create with `tasks:[{action,payload}]` (COMMAND/POWER/BACKUP). Reorderable task list in the create sheet.
- [x] **Passkey registration** — `POST /auth/mfa/webauthn/register/options`, `.../register/verify {response,label?}`, `GET/DELETE .../credentials`. Passkeys section in Security.
- [x] **Profile editing** — `PATCH /account` (firstName/lastName). `EditProfileView` from the Account tab. *(avatar upload deferred)*

## 1.2 — secondary customer features
- [x] **Allocations / ports** — `GET/POST/DELETE /servers/:id/allocations`. `AllocationsView` under Settings → Network (POST needs {ip,port}).
- [ ] **Custom domains / vanity address** — `/servers/:id/domains`, `/vanity-address` *(WEB_APP-only; needs a reliable web-app flag on the client to gate the UI — deferred)*
- [x] **Update game** — `POST /servers/:id/update` (pull latest build). Settings → Maintenance.
- [x] **Auto-restart toggle** — `PATCH /servers/:id/auto-restart {enabled}`; state from `environment.REFX_AUTO_RESTART`. Settings → Behavior.
- [x] **Java version picker (MC)** — `GET/PUT /servers/:id/java-version`. Settings → Java version (auto + majors).
- [x] **level.dat repair (MC)** — `GET .../world/level-dat-status`, `POST .../restore-level-dat`. Minecraft → World recovery.
- [ ] **Full TeamSpeak mgmt** — kick/ban/move/unban/channel-limit/license/audit/bandwidth
- [x] **Backup lock** — `PATCH /servers/:id/backups/:id {isLocked}` (rename N/A — name is create-time only).
- [x] **Workshop reorder** — `PATCH /servers/:id/workshop/reorder {ids}`. EditButton drag.
- [x] **File chmod** — `POST /servers/:id/files/chmod {mode,path}`. Files context menu.
- [x] **Stats history / charts** — `GET /servers/:id/stats/history?range=`. `StatsHistoryView` (Swift Charts) from the overview.
- [x] **Players list** — `GET /servers/:id/players`. Players card on the overview (MC).
- [ ] **Switch-game history** — `GET /servers/:id/game-history`
- [ ] **Bug reports** — `/bugs` (file/comment/attach/track)
- [ ] **Knowledge base** — `GET /support/kb[/:slug]`
- [ ] **Referral program** — `GET /billing/referral`

## 1.3 — staff / admin
- [ ] **Fleet agent update** — `POST /admin/nodes/update-all-agents`
- [ ] **Server transfer** — `POST /admin/servers/:id/transfer`, `GET .../transfers`
- [ ] **Database hosts** — `/admin/database-hosts` (+ test)
- [ ] **Network overview** — `GET /admin/network`
- [ ] **Staff members** — `/admin/staff`
- [ ] **Status incidents + webhooks** — `/admin/status/incidents`, `/admin/status/webhooks`
- [ ] **Homepage alerts** — `/admin/homepage-alerts`
- [ ] **Growth analytics** — `GET /admin/growth`
- [ ] **Support settings** — canned responses, KB authoring, ticket categories
- [ ] **Bug triage** — `/admin/bugs`
- [ ] **Settings hub (rest)** — vanity, referrals, backup-storage, express-backups
- [ ] **Node extras** — maintenance mode, TLS cert pin, DB-host test, backups fleet stats, bootstrap token

## Not applicable
- SSH keys — the panel has none (SFTP is password-only). No parity item.
