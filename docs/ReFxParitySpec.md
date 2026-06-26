# ReFx Parity Spec (Android)

Authoritative parity spec for the native-Android port of the ReFx app, extracted
**from source** in `ReFxFrank/ReFxHostingApp` (iOS, reference implementation).
Every value is cited `path:line` relative to the iOS repo. Where a value was
approximated by the existing Android scaffold, the correction is in **§ Delta**.
Backend is fixed — do not change it.

App is **dark-only** (`ReFxApp/App/ReFxAppApp.swift:24` forces `.preferredColorScheme(.dark)`;
no `UIUserInterfaceStyle`; colorsets are single-appearance).

---

## §0 — Assumptions check (verify/correct each)

1. **REST base `https://api.refx.gg/api/v1`, web `https://refx.gg`, socket `/ws/console`, legal `{web}/privacy|terms|support`.** ✅ correct. (`AppConfig.swift` origins; `ConsoleSocket.swift:111`; `AccountView` legal rows.)
2. **Envelope `{success,data}` / `{success,error{message,code}}`.** ✅ for detail calls; list calls use `{ data:[E], meta }` (no `success` wrapper assumption needed). `send` falls back to decoding `T` directly if unwrap fails (`APIClient.swift:46-72`).
3. **Pagination `{items, meta, hasMore}`.** ⚠ **partially wrong.** The WIRE shape is `{ data: [E], meta: { page, pageSize, total, totalPages } }` (`APIEnvelope.swift:10-20`). There is **no `hasMore` and no `items` on the wire** — `Page.items` is the mapped `data`, and `hasMore` is **computed** `page < totalPages`. Compute it client-side.
4. **Auth: `POST auth/login {email,password}` → tokens; 2FA second step; `POST auth/refresh {refreshToken}`; `POST auth/logout`.** ✅ with detail: login body is `{email, password, totp?, rememberMe?}`; if MFA needed the login response is an MFA challenge `{mfaToken, methods}` and you call **`POST auth/mfa/verify {mfaToken, code, method}`** (method ∈ `"totp"|"recovery"`); logout body is `{refreshToken}` (`AuthAPI.swift:22-36`).
5. **Enum raw values are lowercase (`"running"`, `"admin"`).** ❌ **WRONG — this is the big one.** Data-model enums use **UPPERCASE SCREAMING_SNAKE_CASE**: `RUNNING`, `ADMIN`, `SWITCHING_GAME`, `PENDING_PAYMENT`, `PAST_DUE`, `GIFT_CARD`, etc. (full tables in §4). Only a handful use lowercase case-name raws (`EmailTheme` dark/light, `PayPalMode` sandbox/live, `MFAMethod` totp/recovery/webauthn, `PlanChangeResult.Status` applied/scheduled/invoiced) and the **power signal** strings are lowercase `start|stop|restart|kill`. Refresh returns a rotated `{accessToken, refreshToken}` each time; single-flight refresh on 401.
6. **Money = integer minor units + ISO currency.** ✅ correct (`Money.swift:6`).
7. **Dates ISO-8601 with and without fractional seconds.** ✅ correct (`APIClient.swift:143`).
8. **Push `POST account/push-tokens {token, platform:"android"}`, `DELETE account/push-tokens/{token}`.** ✅ correct (iOS sends `"ios"`; Android → `"android"`) (`AccountService.swift:58-66`).

---

## §1 — Design tokens (exact)

The hex helper (`Theme.swift:15-24`) treats 6-digit hex as opaque. Tokens are dark-only.

### 1a. Color tokens — `ReFxApp/Core/DesignSystem/Theme.swift`
| token | source | hex | notes |
|---|---|---|---|
| appBackground | Theme.swift:29 | `#0A111D` | screen base |
| appBackgroundDeep | Theme.swift:30 | `#070B12` | gradient floor |
| appPanel | Theme.swift:31 | `#0F1828` | glass card base (non-elevated) |
| appCard | Theme.swift:32 | `#101A2B` | elevated base |
| appCardElevated | Theme.swift:33 | `#13203A` | skeleton fill |
| appPopover | Theme.swift:34 | `#0C1422` | field background |
| appPrimary | Theme.swift:37 | `#0072FF` | brand blue |
| appPrimaryDeep | Theme.swift:38 | `#0052CC` | |
| appSecondary | Theme.swift:39 | `#58A7D3` | |
| appAccent | Theme.swift:40 | `#13203A` | |
| appForeground | Theme.swift:43 | `#EEF6FF` | bright text |
| appForegroundStrong | Theme.swift:44 | `#F3F8FF` | |
| appAccentText | Theme.swift:45 | `#7DB7FF` | |
| appHighlight | Theme.swift:46 | `#9DCCFF` | |
| appTextSecondary | Theme.swift:47 | `#D8EAFF` @ 0.72 | |
| appMuted | Theme.swift:48 | `#BCD8FF` @ 0.56 | |
| appLabel | Theme.swift:49 | `#8CC4FF` @ 0.70 | |
| appBorder | Theme.swift:52 | white @ 0.08 (`#14FFFFFF`) | |
| appBorderSoft | Theme.swift:53 | white @ 0.05 (`#0DFFFFFF`) | |
| appBorderBlue | Theme.swift:54 | `#0072FF` @ 0.22 | |
| appSuccess | Theme.swift:57 | `#3FB9A6` | teal-green |
| appWarning | Theme.swift:58 | `#F5A623` | amber |
| appDestructive | Theme.swift:59 | `#E5565B` | red |

### 1b. Asset catalog
| asset | source | hex | notes |
|---|---|---|---|
| AccentColor | Assets.xcassets/AccentColor.colorset/Contents.json:6 | `#0072FF` | = appPrimary, global tint |
| LaunchBackground | LaunchBackground.colorset/Contents.json:6 | `#070E18` | launch bg |

### 1c. Geometry & gradients (`Theme` enum, Theme.swift:64-99)
- `cornerRadius = 16` (cards/panels) · `cornerRadiusSmall = 12` (buttons/fields/chips) · `cardPadding = 14` · `spacing = 12` · `screenMargin = 16`
- `screenGradient`: top→bottom `#0A111D`→`#070B12`
- `glassOverlay`: white@0.05→white@0.012
- `borderGradient`: white@0.14→white@0.04→rgba(0,114,255,0.10)
- `primaryGradient`: `#1A86FF`→`#0059D6`

### 1d. Surfaces / shadow / glow (`GlassSurface`, Theme.swift:107-185)
`.cardSurface(elevated:glow:)` radius 16; fill appCard(elevated)/appPanel + glassOverlay + top white@0.10 highlight (`.plusLighter`, op 0.6); border `borderGradient` lineWidth 1; **drop shadow black@0.45 r14 y8**; glow (when set) `appPrimary@0.35` stroke + shadow r10. `glassInset` radius 12. `screenBackground()` = screenGradient + radial `appPrimary@0.16`→clear at (0.85,0.05) endRadius 420. Reduce-Transparency → solid fills, appBorder, no shadow/glow.

### 1e. Type (system / SF; no custom font)
Eyebrow `.caption2.semibold` tracking **1.4** uppercased appLabel (ReFxControls.swift:110-113); StatePill `.caption2.bold` tracking **0.8** (StatePill.swift:23-24); StatusChip tracking **0.7** (SupportListView.swift:108-109); RoleBadge tracking 0.8 (AccountView.swift:143-144); StatCard value `.title3.semibold.monospacedDigit` (Components.swift:86); buttons `.callout.semibold` (ReFxControls.swift:19,48,71); EmptyState title `.headline`, message `.subheadline` appMuted. `.monospacedDigit()` at Components.swift:57,63,86; `.monospaced()` (IP:port) Components.swift:115.

### 1f. Haptics
Impact `.medium` on row taps/power/submit (ServerDetailViewModel.swift:122, AdminUserDetailView.swift:135/153/159/365, NodeAdminView.swift:170/175/197, AdminCreateServerView.swift:264, AddNodeView.swift:182, PowerControlsView.swift:66); `.rigid` on destructive-confirm (AdminUserDetailView.swift:265, PowerControlsView.swift:25/63, PlatformAlertsView.swift:130); `notificationOccurred(.success)` on copy/save (Components.swift:106, ServerSettingsView.swift:71, FileEditorView.swift:69, BackupsView.swift:47, AddNodeView.swift:208); `.warning` (PowerControlsView.swift:45). → Compose `performHapticFeedback`.

---

## §2 — Component inventory

`ReFxApp/Core/DesignSystem/**`:
- **GlassCard** (Components.swift:7-19) — `(padding=14, elevated=false, glow=false, content)`; `.cardSurface(elevated:glow:)`.
- **ResourceGauge** (Components.swift:25-67) — circular 80×80, track white@0.06 lw9, progress AngularGradient round-cap; **tint by fraction: <0.7 appPrimary, <0.9 appWarning, else appDestructive** (34-40).
- **StatCard** (Components.swift:73-93) — Eyebrow title + value `.title3.semibold.monospacedDigit`; padding 14 `.cardSurface()`.
- **CopyChip** (Components.swift:98-128) — copies to pasteboard + success haptic; COPY→COPIED 1.4 s; `.glassInset()` r12.
- **cardSurface / glassInset / screenBackground** (Theme.swift:107-185) — see §1d.
- **Buttons** (ReFxControls.swift:11-96): all RoundedRect r12, `.callout.semibold`, vpad 11 hpad 18 minHeight 30.
  - `.refxPrimary(fullWidth=true)`: fill primaryGradient + highlight; border white@0.18; shadow appPrimary@0.45 r12 y6; disabled op 0.5; pressed scale 0.98 brightness −0.04.
  - `.refxSecondary`: fill appCard+glassOverlay; fg appForeground; border appBorder→appBorderBlue (pressed).
  - `.refxDestructive`: fill appDestructive@0.14; fg appDestructive; border appDestructive@0.35→0.6.
- **Eyebrow** (ReFxControls.swift:101-116), **SectionHeader** (119-137: Eyebrow + Spacer + trailing), **refxField(focused:)** (143-159: fill appPopover, focus border appPrimary@0.7 + shadow).
- **StatePill** (StatePill.swift:7-59) — dot 7×7 + uppercase `.caption2.bold` tracking 0.8; bg color@0.12, Capsule border color@0.35, fg color; running/transitional pulse.
- **LoadState / AsyncStateView** (LoadState.swift:6-48) — `LoadState<Value> = .idle|.loading|.loaded(Value)|.failed(APIError)`; `AsyncStateView(state,isEmpty,emptyTitle="Nothing here yet",emptyMessage="",retry,content,skeleton)`.
- **ErrorStateView** (50-74) icon `exclamationmark.triangle.fill` appWarning + "Try again" refxPrimary; **EmptyStateView** (76-96) icon `tray` appLabel + title/message; **SkeletonBlock** (99-115) `(height=16)` RoundedRect r6 fill appCardElevated, shimmer 0.45↔0.9.

Reusable in `Features/**`:
- **StatusChip** (SupportListView.swift:104-116) `(text,color)` uppercase `.caption2.bold` tracking 0.7; bg color@0.14, Capsule border color@0.35, fg color.
- **RoleBadge** (AccountView.swift:140-151) `(role)` bg appPrimary@0.14 border appPrimary@0.35 fg appAccentText.
- **ManageRow** (ServerDetailView.swift:230-247) `(icon,title,subtitle,accent=appPrimary)` icon w26 + title/subtitle + chevron.
- **ComingSoonView** (SupportListView.swift:120-139).

### State → token maps (the whole point)
- **ServerState** (StatePill.swift:49-58): running→appSuccess; starting/stopping/installing/reinstalling/switchingGame/transferring→appWarning; offline→appMuted; crashed/suspended/pendingPayment→appDestructive; unknown→appMuted. (pulse set = the warning group + running.)
- **NodeState** (AdminModels.swift:20-27): online→appSuccess; degraded/maintenance/provisioning→appWarning; offline→appDestructive; unknown→appMuted.
- **InvoiceState** (InvoiceDetailView.swift:191-200): paid→appSuccess; open→appWarning; void/uncollectible→appDestructive; draft/refunded/unknown→appMuted.
- **PaymentState** (AdminBillingView.swift:306-313, view-level): succeeded→appSuccess; pending→appWarning; failed→appDestructive; refunded/unknown→appMuted.
- **SubscriptionState** (BillingView.swift:195-201, view-level): active/trialing→appSuccess; pastDue/suspended→appWarning; canceled/expired/unknown→appMuted.
- **TicketState** (Ticket.swift:30-37): open/pendingAgent→appPrimary; pendingCustomer→appWarning; resolved→appSuccess; closed/archived/unknown→appMuted.
- **TicketPriority** (Ticket.swift:51-57): urgent→appDestructive; high→appWarning; low/normal/unknown→appMuted.
- **AlertSeverity** (AdminModels.swift:268-282): info→appPrimary; warning→appWarning; critical→appDestructive; unknown→appMuted (icons: critical `exclamationmark.octagon.fill`, warning `exclamationmark.triangle.fill`, else `info.circle.fill`).
- **BackupState** (Backup.swift:29-36): completed→appSuccess; failed→appDestructive; pending/inProgress→appWarning; unknown→appMuted.
- **ConsoleSocket state** (ServerDetailView.swift:220-226): connected→appSuccess; connecting/reconnecting→appWarning; else appMuted.

> Status-chip pattern is uniform: bg = color@0.12–0.14, Capsule border color@0.35 lw1, fg = color, uppercase bold caption2.

---

## §3 — Data models (exact field names)

> JSON keys = Swift property names unless a CodingKeys remap is noted. Mark optionals exactly as shown.

### Account
**CurrentUser** (User.swift:26, `GET auth/me`): id, email, firstName?, lastName?, globalRole(UserRole), avatarUrl?, creditBalanceMinor?, permissions[String]?, totpEnabledAt(Date?). Computed: displayName, initials, isTotpEnabled.
**OrderProfile** (OrderModels.swift:98, decoded from `GET account`): id, email, emailVerifiedAt?, firstName?, lastName?, phone?, addressLine1?, addressLine2?, city?, region?, postalCode?, country?, creditBalanceMinor?. Computed: emailVerified, creditBalance, hasAddress, needsState, orderReady.
**UpdateProfileBody** (Encodable, OrderModels.swift:124): firstName,lastName,phone,addressLine1,addressLine2,city,region,postalCode,country — all String? nil-default.

### Server + sub-resources
**Server** (Server.swift:83): id, shortId, name, description?, state(ServerState), cpuCores(Double?), memoryMb?, diskMb?, slots?, suspendedAt(Date?), template(GameTemplateRef?), node(NodeRef?), primaryAllocation(Allocation?). Computed: gameName, connectionString.
- **GameTemplateRef** (Server.swift:67): id?, name?, slug?, supportsWorkshop(Bool?).
- **NodeRef** (Server.swift:76): name?, fqdn?.
- **Allocation** (Server.swift:56): id, ip, port(Int), alias?, isPrimary(Bool); connectionString = `alias ?? ip` + `:port`.
**LiveStats** (Stats.swift:5, `GET stats`): state?, cpuPct(Double), memUsedMb(Double), memTotalMb(Double?), diskUsedMb(Double), netRxBytes(Double), netTxBytes(Double), players(Int?), uptimeMs(Double?).
**StatsFrame** (Stats.swift:19, socket `stats`): serverId?, cpuPct, memUsedMb, diskUsedMb, netRxBytes, netTxBytes, state?, players? (no memTotalMb).

### Tickets
**Ticket** (Ticket.swift:61): id, number(Int), subject, state(TicketState), priority(TicketPriority), createdAt(Date), updatedAt(Date?).
**TicketDetail** (Ticket.swift:94): id, number, subject, state, priority, createdAt, messages[TicketMessage].
**TicketMessage** (Ticket.swift:85): id, body, isInternal(Bool?), createdAt, author(TicketAuthor?).
**TicketAuthor** (Ticket.swift:71): id, email?, firstName?, lastName?, globalRole(UserRole?).

### Billing (customer)
**Invoice** (CustomerBillingModels.swift:13): id, number, userId, subscriptionId?, state(InvoiceState), currency, subtotalMinor, discountMinor, couponCode?, taxMinor, totalMinor, amountPaidMinor, taxType?, taxRatePct(Double?), dueAt?, paidAt?, createdAt, lineItems[InvoiceLineItem]?, payments[InvoicePayment]?.
**InvoiceLineItem** (45): id, invoiceId, description, quantity(Int), unitMinor, amountMinor.
**InvoicePayment** (58): id, invoiceId, gateway, gatewayRef?, amountMinor, currency, state(PaymentState), failureReason?, createdAt.
**SubscriptionListItem** (84): id, productId, priceId, interval(BillingInterval), slots, state(SubscriptionState), currentPeriodStart, currentPeriodEnd, cancelAtPeriodEnd(Bool), autoRenew(Bool), gateway, createdAt, product(ProductRef), hardwareTier(TierRef?), servers[ServerRef], renewalAmountMinor, currency.
 - ProductRef(107): id, name, type(ProductType), billingModel(BillingModel), perSlot(Bool).
 - TierRef(114): id, name, cpuCores(Double), memoryMb, diskMb.
 - ServerRef(121): id, shortId, name, **state(String — raw, not enum)**.
**Subscription** (130): id, userId, productId, priceId, hardwareTierId?, interval, slots, state, currentPeriodStart, currentPeriodEnd, cancelAtPeriodEnd, autoRenew, gateway, createdAt, updatedAt.
**PaymentMethod** (175): id, userId, gateway, gatewayRef, brand?, last4?, expMonth(Int?), expYear(Int?), isDefault(Bool), createdAt.
**CreditBalance** (150): balanceMinor, transactions[CreditTransaction]. **CreditTransaction** (158): id, userId, amountMinor(signed), reason(CreditReason), note?, invoiceId?, actorId?, createdAt.
**BillingConfig** (202): stripe{configured,publishableKey?}, paypal{configured}. Results: **PayInvoiceResult** (73: paid, checkoutUrl?, reason?), **PayPalCaptureResult** (79: paid).

### Catalog
**CatalogProduct** (OrderModels.swift:10): id, type(ProductType), billingModel(BillingModel), name, slug, description?, isActive, allowedTemplateIds[String], perSlot(Bool), gameTemplateId?, minSlots, maxSlots, slotStep, prices[CatalogPrice], hardwareTiers[CatalogTier].
**CatalogPrice** (32): id, productId, hardwareTierId?, interval(BillingInterval), currency, amountMinor, isActive.
**CatalogTier** (45): id, productId, name, description?, cpuCores(Double), memoryMb, diskMb, recommendedPlayers(Int?), isRecommended, isActive, sortOrder, prices[CatalogPrice].
**CatalogTemplate** (65): id, name, slug, description?, author, category(Category?), recCpuCores(Double), recMemoryMb, recDiskMb, supportsLinux, supportsWindows, variables[CatalogTemplateVariable]. Category(79): id, name, slug, iconUrl?.
**CatalogTemplateVariable** (82): id, envName, displayName, description?, type(VariableType), defaultValue?, userEditable, userViewable, sortOrder.
**PlacementNode** (94): id, name. **Region** (AdminConfigModels.swift:617): id, code, name, country.
Order DTOs: **CreateOrderBody** (138), **OrderResult** (155), **CouponValidateResult** (165), **GiftCardLookupResult** (173) — see §5 verbatim.

### Admin
**AdminUser** (AdminModels.swift:107): id, email, firstName?, lastName?, globalRole(UserRole?), state(String?).
**AdminUserDetail** (124) — **CodingKeys: `counts` ⇐ `_count`** (138): id, email, firstName?, lastName?, globalRole?, state(String?), createdAt?, emailVerifiedAt?, ownedServers[AdminServerRef], subscriptions[AdminSubscription], invoices[AdminInvoice], `_count`→counts(Counts?).
 - Counts(144): ownedServers(Int?), subscriptions(Int?), tickets(Int?).
 - AdminServerRef(160): id, shortId?, name, state(ServerState), node(NodeNameRef?{name?}).
 - AdminSubscription(169): id, state(String), interval(String?), gateway?, currentPeriodEnd?, product(ProductRef?{id?,name?,type?}). (raw String state/interval/type.)
 - AdminInvoice(183): id, number?, state(String), currency, totalMinor, amountPaidMinor(Int?), createdAt?, paidAt?.
**NodeAdmin** (36): id, name, fqdn?, state(NodeState), agentVersion?, maintenance(Bool?), region(RegionRef?{name?,code?}), memoryMb?, diskMb?. **NodePing** (49): ms(Double?), reachable(Bool), heartbeatAgeMs(Double?). **AgentLatest** (55): latest?. **CreateNodeResult** (98): id?, name?, bootstrapToken.
**AdminGameTemplate** (AdminConfigModels.swift:391): id, categoryId?, category(GameCategory?), name, slug, author, description?, version(Int), deployMethods[DeployMethod], supportsLinux, supportsWindows, dockerImages(JSONValue?), steamAppId(Int?), startupCommand, recCpuCores(Double), recMemoryMb, recDiskMb, isPublished, featured, sortOrder, tags[String]?, variables[TemplateVariable]?.
**GameCategory** (371): id, name, slug, iconUrl?. **TemplateVariable** (378): id, templateId, envName, displayName, description?, type(VariableType), defaultValue?, userEditable, userViewable, sortOrder.
**Coupon** (434, has `_count`): id, code, description?, kind(CouponKind), value(Int), currency, minSubtotalMinor(Int?), maxRedemptions(Int?), timesRedeemed(Int), maxPerUser(Int?), startsAt?, expiresAt?, isActive, `_count`(Count?{redemptions}).
**GiftCard** (487): id, code, initialBalanceMinor, balanceMinor, currency, isActive, expiresAt?, note?.
**Role** (580, `_count`{users}): id, key, name, description?, isSystem(Bool), permissions[String], _count?. **AdminPermissionCatalog** (597): wildcard(String), permissions[String].
**AuditEntry** (AdminModels.swift:229): id, actorId?, action, targetType?, targetId?, ip?, createdAt.
**AdminAlert** (286): id, severity(AlertSeverity?), title, body, isActive, startsAt?, endsAt?, createdAt?.
**AdminMetrics** (200): totals(Totals{users,servers,nodesOnline,openTickets,activeSubscriptions,mrrMinor,mrrCurrency?}), serversByState[String:Int], nodes[NodeMetric{id,name,cpuPct,memPct,diskPct}].
**BillingSummary** (518): currency, revenueMinor, outstandingMinor, activeSubscriptions, openInvoices, paidInvoices.
**AdminOrder** (531), **AdminBillingInvoice** (543), **Payment** (560: id, gateway, amountMinor, currency, state(PaymentState), failureReason?, createdAt, invoice(InvoiceRef{id,number,user})), **EmbeddedUser** (208: id, email, firstName?, lastName?), settings masks **EmailConfigMasked/SteamConfigMasked/GatewayConfigMasked** (638/661/676).

### Misc
**AppNotification** (AppNotification.swift:4): id, title, body, readAt?, createdAt. **UnreadCount** (15): unread(Int).
**Money** (Money.swift:6): minorUnits(Int), currency(String) — always integer minor units + ISO code.
**Page<E>** (in-memory, APIEnvelope.swift:23): items[E], meta(PageMeta), computed hasMore. Wire: **PaginatedEnvelope** {data[E], meta} + **PageMeta**{page,pageSize,total,totalPages}. **APIEnvelope<T>** {success, data}.
Server sub-resources: **SubUser** (SubUser.swift:4: id, state(String?), permissions[String], user(SubUserAccount?{id,email})), **ServerDatabase** (18), **Schedule**/**ScheduleTask** (31/24), **Backup** (41), **FileEntry** (6: name, path, isDir, size(Int), mode?, modifiedAt(String? raw)), **VoiceInfo/VoiceStatus**, **WorkshopMod**, **ServerVariable/StartupConfig** (ServerSettings.swift:10/4), **UpgradeOptions/UpgradePreview/PlanChangeResult** (ServerUpgradeModels.swift:7/54/81), **DashboardSummary** (5), **TokenResponse** (AuthModels.swift:6).

---

## §4 — Enums (exact raw values + the `.unknown` story)

| Enum | raw values (verbatim, in order) | source | .unknown? |
|---|---|---|---|
| ServerState | INSTALLING, OFFLINE, STARTING, RUNNING, STOPPING, CRASHED, SUSPENDED, REINSTALLING, SWITCHING_GAME, TRANSFERRING, PENDING_PAYMENT | Server.swift:5 | yes |
| UserRole | PENDING_CUSTOMER, CUSTOMER, SUPPORT, ADMIN, OWNER | User.swift:5 | yes |
| TicketState | OPEN, PENDING_CUSTOMER, PENDING_AGENT, RESOLVED, CLOSED, ARCHIVED | Ticket.swift:4 | yes |
| TicketPriority | LOW, NORMAL, HIGH, URGENT | Ticket.swift:42 | yes |
| ProductType | GAME_SERVER, VOICE_SERVER, VPS, DEDICATED, ADDON | AdminConfigModels.swift:17 | yes |
| BillingModel | HARDWARE_TIER, PER_SLOT | AdminConfigModels.swift:41 | yes |
| BillingInterval | WEEKLY, BIWEEKLY, MONTHLY, QUARTERLY, SEMIANNUAL, ANNUAL | AdminConfigModels.swift:59 | yes |
| DeployMethod | DOCKER, NATIVE_PROCESS, WINDOWS_CONTAINER, SANDBOX | AdminConfigModels.swift:87 | yes |
| VariableType | STRING, NUMBER, BOOLEAN, ENUM, SECRET | AdminConfigModels.swift:101 | yes |
| CouponKind | PERCENT, FIXED | AdminConfigModels.swift:116 | yes |
| InvoiceState | DRAFT, OPEN, PAID, VOID, UNCOLLECTIBLE, REFUNDED | AdminConfigModels.swift:134 | yes |
| PaymentState | PENDING, SUCCEEDED, FAILED, REFUNDED | AdminConfigModels.swift:150 | yes |
| SubscriptionState | TRIALING, ACTIVE, PAST_DUE, CANCELED, SUSPENDED, EXPIRED | AdminConfigModels.swift:164 | yes |
| CreditReason | ADMIN_GRANT, REFUND, GIFT_CARD, INVOICE_PAYMENT, ADJUSTMENT | AdminConfigModels.swift:180 | yes |
| NodeState | PROVISIONING, ONLINE, OFFLINE, MAINTENANCE, DEGRADED | AdminModels.swift:6 | yes |
| AlertSeverity | INFO, WARNING, CRITICAL | AdminModels.swift:249 | yes |
| BackupState | PENDING, IN_PROGRESS, COMPLETED, FAILED | Backup.swift:4 | yes |
| ScheduleAction | COMMAND, POWER, BACKUP | Schedule.swift:3 | yes |
| DbEngine | MYSQL, MARIADB | ServerDatabase.swift:3 | yes |
| NodeOS | LINUX, WINDOWS | AdminModels.swift:75 | no (UI-only, not Codable) |
| EmailTheme | dark, light | AdminConfigModels.swift:195 | **no** |
| PayPalMode | sandbox, live | AdminConfigModels.swift:200 | **no** |
| MFAMethod | totp, recovery, webauthn | AuthModels.swift:17 | yes |
| PlanChangeResult.Status | applied, scheduled, invoiced | ServerUpgradeModels.swift:88 | yes (manual, non-Codable) |

UI/infra enums (NOT wire DTOs): ServerSection, PowerSignal (`start|stop|restart|kill`), several `Tab` enums, TokenKey, HTTPMethod.

**Permissive decoder (verbatim, Server.swift:19-22):**
```swift
init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = ServerState(rawValue: raw) ?? .unknown
}
```
Used by **every** Codable String enum with `.unknown`. Exceptions: EmailTheme & PayPalMode (no `.unknown`, synthesized Codable — out-of-set value throws); NodeOS (not Codable); PlanChangeResult.Status (`?? .unknown` applied in computed accessor, not a decoder).

**Per-server permission strings** (`Permission.swift:7-36` canonical; `PermissionCatalog.swift:17-64` editor superset):
`control.start, control.stop, control.restart, control.power, control.reinstall, control.resize, console.read, console.command, files.read, files.write, files.archive, files.delete, files.sftp, backup.read, backup.create, backup.restore, backup.download, backup.delete, allocation.read, schedule.read, schedule.create, schedule.update, schedule.delete, subuser.read, startup.update, settings.read, settings.update` plus editor-only `database.read/create/delete`, `user.read/create/update/delete`. Role wildcard = `"*"`.

---

## §5 — Endpoint catalogue

Base `/api/v1` (`APIClient.swift:117`). `send`→unwrap `{success,data}`→T (fallback raw T); `sendPaginated`→`{data:[E],meta}`→Page<E>; `sendVoid`→ignore. Bearer attached unless `authenticated==false`; only the 7 `auth/*` token routes are unauthenticated. 401 on authed route → single-flight `POST auth/refresh` + retry (`APIClient.swift:96`).

### Auth · Account · Security · Push · Notifications
| Method + path | body | response | source |
|---|---|---|---|
| POST auth/login | {email,password,totp?,rememberMe?} | TokenResponse / MFA challenge | AuthAPI.swift:22 |
| POST auth/mfa/verify | {mfaToken,code,method} | TokenResponse | AuthAPI.swift:26 |
| POST auth/refresh | {refreshToken} | TokenResponse | AuthAPI.swift:30 |
| POST auth/logout | {refreshToken} | void | AuthAPI.swift:36 |
| GET auth/me | — | CurrentUser | AuthAPI.swift:42 |
| POST auth/mfa/webauthn/login/options | {mfaToken} | PasskeyOptions | AuthAPI.swift:46 |
| POST auth/mfa/webauthn/login/verify | {mfaToken,response} | TokenResponse | AuthAPI.swift:51 |
| POST auth/mfa/totp/enroll | — | TotpEnrollment | AccountService.swift:71 |
| POST auth/mfa/totp/verify | {code} | RecoveryCodes | AccountService.swift:75 |
| DELETE auth/mfa/totp | — | void | AccountService.swift:79 |
| GET account | — | CurrentUser / OrderProfile | AccountService.swift:9 |
| PATCH account | UpdateProfileBody | void | OrderCheckoutServices.swift:61 |
| GET account/notifications | — | [AppNotification] | AccountService.swift:16 |
| GET account/notifications/unread-count | — | UnreadCount | AccountService.swift:20 |
| POST account/notifications/{id}/read | — | void | AccountService.swift:24 |
| POST account/notifications/read-all | — | void | AccountService.swift:28 |
| GET account/sessions | — | [UserSession] | AccountService.swift:34 |
| DELETE account/sessions/{id} | — | void | AccountService.swift:38 |
| POST account/password | {currentPassword,newPassword} | void | AccountService.swift:45 |
| POST account/push-tokens | {token,platform} | void | AccountService.swift:59 |
| DELETE account/push-tokens/{token} | — | void | AccountService.swift:63 |
| GET account/api-keys | — | [ApiKey] | AccountService.swift:85 |
| POST account/api-keys | {name,scopes[]} | CreatedApiKey | AccountService.swift:89 |
| DELETE account/api-keys/{id} | — | void | AccountService.swift:94 |
| GET dashboard | — | DashboardSummary | DashboardService.swift:7 |

### Servers
| Method + path | body | response | source |
|---|---|---|---|
| GET servers | q page,pageSize,q? | Page<Server> | ServersService.swift:13 |
| GET servers/{id} | — | Server | ServersService.swift:17 |
| POST servers/{id}/power | {signal} (start\|stop\|restart\|kill) | void | ServersService.swift:22 |
| POST servers/{id}/command | {command} | void | ServersService.swift:27 |
| GET servers/{id}/stats | — | LiveStats | ServersService.swift:33 |
| GET servers/{id}/upgrade/options | — | UpgradeOptions | ServersServiceUpgrade.swift:7 |
| POST servers/{id}/upgrade/preview | UpgradeServerDTO | UpgradePreview | ServersServiceUpgrade.swift:11 |
| POST servers/{id}/upgrade | UpgradeServerDTO | PlanChangeResult | ServersServiceUpgrade.swift:15 |
| DELETE servers/{id}/upgrade | — | CancelPlanChangeResult | ServersServiceUpgrade.swift:20 |
| GET servers/{id}/files/list | q path | [FileEntry] | FilesService.swift:11 |
| GET servers/{id}/files/contents | q path | FileContent | FilesService.swift:17 |
| POST servers/{id}/files/write | {path,content} | void | FilesService.swift:24 |
| POST servers/{id}/files/mkdir | {path} | void | FilesService.swift:29 |
| POST servers/{id}/files/rename | {from,to} | void | FilesService.swift:35 |
| POST servers/{id}/files/delete | {paths[]} | void | FilesService.swift:39 |
| GET servers/{id}/files/download-url | q path | SignedURL | FilesService.swift:45 |
| GET servers/{id}/backups | q page,pageSize | Page<Backup> | BackupsService.swift:9 |
| POST servers/{id}/backups | {name} | void | BackupsService.swift:16 |
| POST servers/{id}/backups/{backupId}/restore | — | void | BackupsService.swift:20 |
| DELETE servers/{id}/backups/{backupId} | — | void | BackupsService.swift:24 |
| GET servers/{id}/backups/{backupId}/download | — | SignedURL | BackupsService.swift:29 |
| GET servers/{id}/schedules | — | [Schedule] | SchedulesService.swift:9 |
| POST servers/{id}/schedules | {name,cron,onlyWhenOnline,isActive,tasks[{action,payload}]} | void | SchedulesService.swift:30 |
| PATCH servers/{id}/schedules/{sid} | {isActive} | void | SchedulesService.swift:14 |
| POST servers/{id}/schedules/{sid}/run | — | void | SchedulesService.swift:18 |
| DELETE servers/{id}/schedules/{sid} | — | void | SchedulesService.swift:22 |
| GET servers/{id}/databases | — | [ServerDatabase] | DatabasesService.swift:9 |
| POST servers/{id}/databases | {engine,name,remoteAccess?} | ServerDatabase | DatabasesService.swift:14 |
| DELETE servers/{id}/databases/{dbId} | — | void | DatabasesService.swift:20 |
| POST servers/{id}/databases/{dbId}/rotate | — | DatabasePassword | DatabasesService.swift:25 |
| GET servers/{id}/sub-users | — | [SubUser] | SubUsersService.swift:9 |
| POST servers/{id}/sub-users | {email,permissions[]} | void | SubUsersService.swift:13 |
| PATCH servers/{id}/sub-users/{suid} | {permissions[]} | void | SubUsersService.swift:18 |
| DELETE servers/{id}/sub-users/{suid} | — | void | SubUsersService.swift:23 |
| GET servers/{id}/mods/context · /mods/search(q) · /mods/installed | — | ModContext / [ModSearchResult] / InstalledModsResponse | ModsService.swift:9-18 |
| POST servers/{id}/mods/install {projectId} · DELETE /mods/{filename} | | void | ModsService.swift:22-27 |
| modpacks: GET /modpacks/search(q),/modpacks/versions(projectId),/modpacks/installed · POST /modpacks/install{versionId},/modpacks/uninstall | | … | ModpacksService.swift:9-30 |
| workshop: GET /workshop · POST /workshop{input} · PATCH /workshop/{modId}{enabled} · DELETE /workshop/{modId} · POST /workshop/apply | | … | WorkshopService.swift:10-27 |
| PATCH servers/{id}/minecraft | {loader,version?,loaderVersion?} | void | WorkshopService.swift:42 |
| voice: GET /voice,/voice/status · POST /voice/accept-license,/voice/rename{name} | | VoiceInfo/VoiceStatus | ModsService.swift:39-51 |
| GET servers/{id}/switch-game/templates · POST /switch-game {templateId,keepData} | | [GameTemplate] / void | SwitchGameService.swift:10-14 |
| GET/PATCH servers/{id}/startup · GET/PATCH/DELETE /variables · POST /reinstall | see §body | StartupConfig/[ServerVariable]/void | ServerSettingsService.swift:11-33 |

### Catalog (public)
GET catalog/minecraft-versions(loader), /minecraft-builds(loader,version), /products, /templates, /locations(cpuCores,memoryMb,diskMb), /nodes(regionId,cpuCores,memoryMb,diskMb) → {versions}/{builds}/[CatalogProduct]/[CatalogTemplate]/[Region]/[PlacementNode] (CatalogService.swift:14-22, OrderCheckoutServices.swift:7-23).

### Billing
GET billing/credit→CreditBalance · GET billing/invoices(page,pageSize)→Page<Invoice> · GET billing/invoices/{id}→Invoice · POST billing/invoices/{id}/pay(gateway?)→PayInvoiceResult · POST billing/servers/{serverId}/pay(gateway?) · POST billing/paypal/capture(token)→PayPalCaptureResult · GET billing/subscriptions→[SubscriptionListItem] · POST billing/subscriptions/{id}/cancel(atPeriodEnd)→Subscription · POST billing/subscriptions/{id}/resume→Subscription · GET billing/payment-methods→[PaymentMethod] · POST billing/payment-methods/{id}/default→PaymentMethod · DELETE billing/payment-methods/{id} · GET billing/config→BillingConfig · POST orders(CreateOrderBody)→OrderResult · POST billing/coupons/validate{code,subtotalMinor}→CouponValidateResult · POST billing/gift-cards/lookup{code}→GiftCardLookupResult (BillingService.swift:12-84, OrderCheckoutServices.swift:38-47).

### Support
GET support/tickets(page,pageSize,mine?,state?)→Page<Ticket> · GET support/tickets/{id}→TicketDetail · POST support/tickets{subject,body,priority?}→Ticket · POST support/tickets/{id}/messages{body} · PATCH support/tickets/{id}{state?,priority?} (staff) · POST support/tickets/{id}/assign{assigneeId} (staff) (SupportService.swift:15-41).

### Staff / Admin
GET admin/metrics→AdminMetrics · GET admin/servers(page,pageSize,q?)→Page<Server> · DELETE admin/servers/{id} · **POST admin/servers**→Server · GET admin/nodes(pageSize=100)→Page<NodeAdmin> · GET admin/nodes/{id} · **POST admin/nodes**→CreateNodeResult · GET admin/nodes/{id}/ping→NodePing · POST admin/nodes/{id}/restart-agent|update-agent|steam-cache/clear · GET admin/nodes/agent-latest→AgentLatest · GET admin/users(page,pageSize,q?)→Page<AdminUser> · GET admin/users/{id}→AdminUserDetail · PATCH admin/users/{id}{state} · POST admin/users/{id}/verify-email · PATCH admin/users/{id}/role{role} · **POST admin/users/{id}/credit**{amountMinor,reason?,note?} · products/tiers/prices (StaffServiceConfig.swift:11-38) · templates GET/PATCH/DELETE (44-53) · coupons & gift-cards (59-77) · admin/billing/summary, admin/orders, admin/invoices void|mark-paid|delete, admin/payments (83-113) · roles + roles/permissions (123-135) · locations (141-150) · settings email|steam|gateways + email/test (156-174) · admin/audit-logs(page,pageSize=40)→Page<AuditEntry> · admin/alerts GET/POST{severity,title,body,isActive}/PATCH{isActive}/DELETE (StaffService.swift:109-131).

### Critical bodies (verbatim)
```swift
// POST admin/servers — AdminModels.swift:61 (nil optionals omitted)
struct AdminCreateServerBody: Encodable {
    let name: String; let ownerId: String; let nodeId: String; let templateId: String
    var cpuCores: Double? = nil; var memoryMb: Int? = nil; var diskMb: Int? = nil
    var slots: Int? = nil; var swapMb: Int? = nil; var environment: [String:String]? = nil
}
// POST admin/nodes — AdminModels.swift:84
struct CreateNodeBody: Encodable {
    let name: String; let fqdn: String; let regionId: String
    let os: String                 // "LINUX" | "WINDOWS"
    let cpuCores: Int; let memoryMb: Int; let diskMb: Int
    let allocationPortStart: Int; let allocationPortEnd: Int
}
struct CreateNodeResult: Decodable { let id: String?; let name: String?; let bootstrapToken: String } // :98
// POST orders — OrderModels.swift:138
struct CreateOrderBody: Encodable {
    var productId: String; var priceId: String; var templateId: String; var name: String
    var hardwareTierId: String? = nil; var regionId: String? = nil; var nodeId: String? = nil
    var slots: Int? = nil; var couponCode: String? = nil; var giftCardCode: String? = nil
    var useCredit: Bool? = nil; var paymentMethodId: String? = nil; var gateway: String? = nil
    var environment: [String:String]? = nil
}
struct OrderResult: Codable { let serverId: String; let subscriptionId: String; let invoiceId: String; let checkoutUrl: String?; let paid: Bool } // :155
struct CouponValidateResult: Codable { let valid: Bool; let code: String; let kind: CouponKind; let value: Int; let discountMinor: Int } // :165
struct GiftCardLookupResult: Codable { let code: String; let balanceMinor: Int; let currency: String } // :173
struct GrantCreditBody: Encodable { let amountMinor: Int; let reason: CreditReason?; let note: String? } // StaffServiceConfig.swift:179
```
Power signal body key is **`signal`** (not `action`), values `start|stop|restart|kill`.

---

## §6 — Live console (Socket.IO)

`ReFxApp/Core/Realtime/ConsoleSocket.swift`. **Socket.IO protocol** (not raw WS). Namespace **`/ws/console`** (:111), URL = `socketOrigin` (= apiOrigin).

Bearer passed **two ways**: extra header `Authorization: Bearer <token>` (:109) AND CONNECT payload `{token}` via `socket.connect(withPayload:["token":token])` (:116). Token fetched async first (:84-92). On expiry server disconnects with `error{message:"unauthorized"}` → client refreshes + reconnects.

Manager config (:101-117): `.reconnects(true) .reconnectWait(2) .reconnectWaitMax(15) .reconnectAttempts(-1) .compress .handleQueue(main)`; both transports.

Emit: `command` `{command}` (:76); `subscribe` `{serverId}` on connect (:124). Local echo `> cmd` stream `"input"` (:77).
Listen (:119-175): `.connect`→connected+emit subscribe; `.reconnect`/`.disconnect`→reconnecting; `"subscribed"`→connected; `"error"` `{message}` (`unauthorized`→refresh; `forbidden`→`.forbidden` + line "You don't have console access to this server."); `"console"` `{line, stream="stdout"}`→append; `"stats"`→StatsFrame (state→ServerState→liveState); `"power"` `{state}`→ServerState→liveState. ConsoleLine `{text,stream}`, `isError = stream=="stderr"`; buffer cap **2000** (FIFO). ConnectionState: idle/connecting/connected/reconnecting/forbidden/failed(String). Auth-expiry reconnect refreshes once (`didRefreshForAuth` guard), reset on connect.

---

## §7 — Push notifications (client contract)

`ReFxApp/Core/Background/PushNotifications.swift`.

Parsed userInfo keys (:132-140): **`type`, `serverId`, `invoiceId`, `ticketId`**. `type` matched by lowercased substring.
Router (:26-38): contains `"server"`+serverId→`.servers` tab + serverId; `"invoice"|"billing"|"payment"`→`.billing` tab + invoiceId(may be nil); `"ticket"|"support"`→`.support` tab + ticketId; fallback serverId→`.servers`. PushTab = servers|billing|support.
Token register (AccountService.swift:58-66): **POST account/push-tokens `{token, platform:"ios"}`** → Android use `"android"`; unregister DELETE `account/push-tokens/{token}`. APNs token hex-encoded.
Triggers: at launch `requestAndRegister()` (auth `[.alert,.sound,.badge]` then register) ; **on signedIn phase** `registerIfAuthorized()` (ReFxAppApp.swift:47-51) — re-register on every sign-in.
Cold-launch (RootView.swift MainTabView): `.onChange(of: pushRouter.tab)` (post-launch) **and** `.onAppear { DispatchQueue.main.async { apply(intent) } }` (cold launch). `apply`: `.servers`→servers tab, **`.billing`→account tab** (billing under Account), `.support`→support tab, then clears `tab=nil`; id targets persist so each tab root deep-pushes. Android: a `PendingRoute` consumed by the NavHost on first composition.

---

## §8 — Screen / view-model specs

**Cross-cutting:** AppLock (Core/Auth/AppLock.swift) biometric gate, key `"refx.appLock.enabled"`, `LAPolicy.deviceOwnerAuthentication`, **fails closed**; lock on background only if enabled & signedIn. Phase machine (RootView.swift:9-23): loading/signedOut/locked/signedIn. Privacy curtain whenever `scenePhase != .active` (ReFxAppApp.swift:29-31,115-124). **FeatureFlags.purchasingEnabled** (FeatureFlags.swift:13-24): DEBUG true; else `productionOverride || receipt=="sandboxReceipt"` → gates in-app checkout (App Store 3.1.3(e)); **Android has no IAP constraint** — treat as always-on or own remote flag.

Tabs (RootView.swift:64-88): Home(DashboardView), Servers, Support, Staff(if isStaff), Account(badge unreadCount).

- **ServersListView/VM:** `GET servers?page&pageSize=25[&q]`, paginate on last row while `page<totalPages`; empty "No servers yet" / "Servers you own or help manage will appear here."; pull-refresh + **periodic 12 s poll (12_000_000_000 ns)** while visible.
- **ServerDetailView/VM:** load `GET servers/{id}` → `GET stats` → console connect; effective state `liveState ?? server.state ?? .unknown`; power `POST power {signal}` with optimistic state + **0.8 s debounce** + confirm dialogs; pendingPayment shows Pay-now → BillingView; drives Live Activity. **ServerSection** (console,files,databases,backups,schedules,minecraft,mods,modpacks,workshop,voice,switchGame,upgrade,settings) `isApplicable`: minecraft/mods/modpacks → minecraft slug; workshop → supportsWorkshop; voice → teamspeak slug; console/switchGame → not voice; else always. webPath: switchGame→"switch-game".
- **BillingView/VM:** parallel `GET billing/credit` + `/subscriptions` + `/invoices`; pay/cancel/resume actions; sub-nav Invoices/PaymentMethods/Credit. Copy: "No subscriptions" / "Plans you purchase appear here."
- **SupportListView/VM:** `GET support/tickets`; empty "No tickets" / "Need help? Open a ticket and our team will respond."; "+"→create; consumes pushRouter.ticketId.
- **AccountView:** reads session; sub-nav Notifications/Security(TOTP+API keys)/Sessions/ChangePassword/PushSettings; About & legal web links; sign out; consumes pushRouter.invoiceId.
- **Staff:** StaffHomeView role-router (SUPPORT→queue only; ADMIN/OWNER→overview+queue+servers+users+nodes+alerts+audit+config). AdminServersView (+AdminCreateServerView: loads templates+nodes+owner picker, POST admin/servers, success "Server created — provisioning on {node}."). NodeAdminView (ping/restart/update/steam-cache; +AddNodeView: GET locations, POST admin/nodes, bootstrap token "Shown once — it can't be retrieved later…"). AdminUserDetailView (state/role/verify-email/credit).

---

## §9 — Tests to mirror (`Tests/ReFxAppTests/*.swift`)

- **AdminProvisioningTests.swift** — encoder = camelCase + iso8601 (:12-18). Asserts `AdminCreateServerBody` exact keys & nil-drop of slots/swapMb (:22); slot-sized drops resource keys (:43); minimal = exactly {name,ownerId,nodeId,templateId} (:55); AdminGameTemplate decode + unknown deployMethod "WARP_DRIVE"→[.unknown] (:63,:92); NodeAdmin permissive (:114,:129); `CreateNodeBody` exact keys incl. os="LINUX", ports (:141); CreateNodeResult token from full payload (:158); CreditReason "LOYALTY_BONUS"→.unknown (:180).
- **AuthRefreshTests.swift** — login persists tokens (:9); MFA challenge w/o persisting (:23); **20 concurrent 401s → exactly 1 refresh** (:40); refresh failure clears session (:61); no-token→false, 0 calls (:75); sequential rotations (:86).
- **OrderCheckoutDecodingTests.swift** — CatalogProduct tiered (empty allowedTemplateIds = all) (:8); per-slot product prices (:44); CatalogTemplate variables (:65); OrderProfile preconditions (US needs state) (:89); OrderResult + CouponValidateResult percent discount (:111).
- **CustomerBillingDecodingTests.swift** — Invoice outstanding = total−paid clamped ≥0 (:9,:36); SubscriptionListItem renewal "/mo" (:51); CreditBalance signed labels (:74); PaymentMethod Visa/PayPal display (:93); PayInvoiceResult variants (:115); BillingConfig (:125).
- **MoneyTests.swift** — USD 2dp; JPY 0dp; KWD 3dp; uppercase normalization; never float (:8-38).
- **ServerUpgradeDecodingTests.swift** — tiered/pending decode; proration dueToday = delta×factor, downgrades charge 0; PlanChangeResult branches incl. "??"→.unknown (:7-85).
- Support: `TestDecoder.swift` (`TestJSON.decode`), `Mocks.swift` (`MockAuthAPI`/`InMemoryTokenStore`).

---

## Delta vs. assumptions (apply to the Android scaffold)

1. **🔴 Enum raw values are UPPERCASE SCREAMING_SNAKE_CASE, not lowercase.** Fix `data/model/Enums.kt`: `RUNNING`, `OFFLINE`, `SWITCHING_GAME`, `PENDING_PAYMENT`, `ADMIN`, `OWNER`, `PENDING_CUSTOMER`, `PAST_DUE`, `GIFT_CARD`, `IN_PROGRESS`, etc. (full §4). The only lowercase ones: EmailTheme/PayPalMode/MFAMethod/PlanChangeResult.Status (case-name raws) and the **power signal** strings `start|stop|restart|kill`. Keep permissive `UNKNOWN` fallback for all except EmailTheme/PayPalMode (no unknown).
2. **🟠 Pagination has no `hasMore`/`items` on the wire** — it's `{ data:[E], meta:{page,pageSize,total,totalPages} }`. Map `data`→items and compute `hasMore = page < totalPages` in the client. Fix `data/api/*` paging.
3. **🟠 Design tokens — use the exact hex in §1a**, not guesses. Primary `#0072FF`, background `#0A111D`, card `#101A2B`, success `#3FB9A6`, warning `#F5A623`, destructive `#E5565B`, and the alpha-bearing text/border tokens. Update `core.design.DesignTokens`. App is dark-only.
4. **🟡 Auth is two-step for MFA:** login may return an MFA challenge `{mfaToken, methods}`; then `POST auth/mfa/verify {mfaToken, code, method}`. Login body includes `totp?`/`rememberMe?`. Fix `AuthApi`.
5. **🟡 401 refresh is single-flight** (one refresh for N concurrent 401s) and the refresh response **rotates** both tokens — persist the new refresh token. Verify `TokenRefresher`.
6. **🟡 Console handshake passes the bearer twice** (header + CONNECT `{token}`) and uses Socket.IO events `command`/`subscribe` (emit) and `console`/`stats`/`power`/`error`/`subscribed` (listen); reconnect 2–15 s infinite; 2000-line cap.
7. **🟡 Push:** set `platform:"android"`; route by lowercased-substring of `type`; register at launch **and** on every signed-in transition; consume a pending route on first NavHost composition (cold launch).
8. **🟢 Confirmed:** base URLs/socket/legal paths; `{success,data}` envelope; money minor-units; dual ISO-8601 dates; push endpoint shape; the `POST admin/servers` / `POST admin/nodes` / `POST orders` / `credit` request bodies (§5 verbatim).
