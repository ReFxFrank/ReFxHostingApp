# App Store submission prep

Everything needed to put ReFx on the App Store. The code-side items are done
(privacy manifest, encryption declaration, purchasing gate). The rest is
copy-paste into App Store Connect plus screenshots you capture from the device.

Bundle ID: `com.refx.app` · Team: `FM8Z8BA64H` · Min iOS 16 · iPhone + iPad.

---

## 1. App Privacy ("nutrition label")  → App Store Connect ▸ App Privacy

This must match `ReFxApp/Resources/PrivacyInfo.xcprivacy` (already committed).
The app does **no tracking** and uses **no analytics/ad SDKs** — the only
third-party SDK is SocketIO (live console transport).

Answer the questionnaire as:

| Data type | Collected? | Linked to user? | Used for tracking? | Purpose |
|---|---|---|---|---|
| Email address | Yes | Yes | No | App Functionality |
| Name | Yes | Yes | No | App Functionality |
| Physical address (billing) | Yes | Yes | No | App Functionality |
| Device ID (APNs push token) | Yes | Yes | No | App Functionality |
| Customer support (ticket messages) | Yes | Yes | No | App Functionality |

Everything else: **Not Collected**. Critically:
- **Payment info → Not Collected by the app.** Card entry happens on the
  hosted web checkout in the browser; the app never sees card numbers.
- No location, no contacts, no photos, no usage data, no identifiers for ads.
- "Used for tracking" is **No** everywhere → no App Tracking Transparency
  prompt required, no tracking domains.

> Note: the table above includes "Customer support" which isn't in the
> machine-readable manifest categories — that's expected; the manifest covers
> the standard data types and the questionnaire is the authoritative privacy
> disclosure.

---

## 2. Export compliance  → already handled

`Info.plist` sets `ITSAppUsesNonExemptEncryption = false` (standard HTTPS/TLS
only = exempt). No per-upload prompt, no CCATS/year-end self-classification
report needed. Nothing to do.

---

## 3. Guideline 3.1.3 (purchasing) — the one to get right

Game-server hosting is a service **consumed outside the app**, so paying by
card is allowed under 3.1.3(e) and must *not* use Apple IAP. To avoid reviewer
subjectivity, **all in-app card-purchase entry points are auto-disabled on
public App Store builds** and stay on the web (`FeatureFlags.purchasingEnabled`
returns false unless it's a Debug or TestFlight build).

**What this means for review:** on the build reviewers install from App Store
Connect (production receipt), there is **no in-app purchase UI at all**. Every
card-purchase surface is gated behind `FeatureFlags.purchasingEnabled`:

| Surface | Where | Hidden on public build |
| --- | --- | --- |
| New-server "+" | `ServersListView` | ✅ |
| Server "Upgrade / change plan" section | `ServerSection.isApplicable` | ✅ |
| Invoice "Pay now" (billing list) | `BillingView` | ✅ |
| Invoice "Pay <amount>" (detail) | `InvoiceDetailView` | ✅ |
| Pending-payment "Pay now" row | `ServerDetailView` | ✅ |
| Login "…or pay an invoice on the web" | `LoginView` footer | ✅ (drops to "Create an account on the web") |

Billing/invoice screens stay **viewable** (read-only) so reviewers can see the
app's billing surface; only the pay *actions* are withheld. Existing servers are
managed; new ones and payments happen on the website. This keeps the app firmly
in "free companion app" territory (3.1.3(f)) and sidesteps the IAP-vs-card
debate entirely.

> ⚠️ **Maintainer note:** if you add any new pay / checkout / "buy" button,
> gate it behind `FeatureFlags.purchasingEnabled` too, or the Review Notes below
> ("no in-app purchase UI at all") stop being true and risk a rejection.

If you ever decide to surface card purchasing in the public build, flip
`FeatureFlags.productionOverride = true` and add review notes citing 3.1.3(e).
Until then, leave it false.

**App Review notes (paste into the Review Notes field):**
> ReFx is a free companion app for an existing game-server hosting service.
> Accounts and servers are purchased on our website; the app manages servers
> the user already owns (console, files, backups, billing history, support).
> There is no digital content or functionality unlocked by purchase inside the
> app, so no in-app purchase is offered. Demo credentials below.

---

## 4. Reviewer demo account  → required (app is login-gated)

The whole app is behind sign-in, so App Review **needs working credentials**
in the "Sign-In Information" section, or it will be rejected for "couldn't
access the app." Provide a demo account that has:
- at least one server (so the server list / detail isn't empty), and
- ideally an invoice and a support ticket (so those tabs show content).

Do **not** give a staff/admin account — use a normal customer so reviewers see
the customer experience. 2FA must be **off** for the demo account (reviewers
can't pass a TOTP prompt).

---

## 5. Store listing copy  → App Store Connect ▸ (version) ▸ App Information

Drafts — tune to taste. Character limits noted.

- **Name (30):** `ReFx — Game Server Hosting`
- **Subtitle (30):** `Manage your servers anywhere`
- **Promotional text (170, editable anytime):**
  `Console, files, backups and live status for your game servers — now with
  push alerts the moment a server needs you.`
- **Keywords (100, comma-separated, no spaces):**
  `game,server,hosting,minecraft,console,ftp,backup,teamspeak,rust,valheim,control,panel`
- **Description:**
  ```
  ReFx puts your game servers in your pocket.

  Manage every server you own from one fast, native app:

  • Live status at a glance — see what's running, down, or needs attention
  • Full web console with command history
  • Browse and edit config files; create and restore backups
  • Schedule automated tasks
  • Install mods, modpacks, and Steam Workshop content
  • Switch games, change plans, and resize resources
  • Billing history, invoices, and support tickets built in
  • Push notifications when a server changes state, an invoice is due, or
    support replies

  ReFx is a free companion to your existing hosting account. Sign in and your
  servers are right there.
  ```
- **Support URL:** `https://refx.gg/support`
- **Marketing URL:** `https://refx.gg` (optional)
- **Privacy Policy URL:** `https://refx.gg/privacy` (required — must be live)

> These same pages are now linked in-app under **Account ▸ About & legal**
> (Privacy Policy, Terms of Service, Help & Support), opened relative to the
> configured web origin (`/privacy`, `/terms`, `/support`). If any of those
> paths differ on the live site, tell me and I'll adjust the links.
- **Category:** Primary `Utilities` (or `Developer Tools`); Secondary optional.
- **Age rating:** 4+ (no objectionable content). Answer the questionnaire all
  "None."

---

## 6. Screenshots  → you capture these

Required sets (App Store Connect accepts the largest size per device and
down-scales):
- **iPhone 6.9"** (e.g. 15/16 Pro Max) — 1320 × 2868. Required.
- **iPad 13"** (universal app) — 2064 × 2752. Required because the app
  targets iPad too.

Suggested 5–6 shots, in order: Servers list (with a couple of servers) →
Server detail → Live console → Files or Backups → Billing/invoices →
Notifications. Use the demo account so they're populated. Capture on device or
the simulator (Cmd-S in the simulator saves a correctly-sized PNG).

---

## 7. Pre-submit checklist

- [ ] Privacy manifest bundled (done — `PrivacyInfo.xcprivacy`)
- [ ] App Privacy questionnaire filled per §1
- [ ] Privacy Policy URL live and entered
- [ ] Demo account created (customer, 2FA off, has a server) and entered in
      Sign-In Information
- [ ] Review notes from §3 pasted
- [ ] Screenshots uploaded (iPhone 6.9" + iPad 13")
- [ ] Name / subtitle / keywords / description entered
- [ ] Build selected (the auto-uploaded TestFlight build)
- [ ] Export compliance — nothing to do (exempt), confirm no prompt
- [ ] Verify on the TestFlight/production build that the new-server "+" is
      hidden (purchasing gate off)
- [ ] Submit for review
