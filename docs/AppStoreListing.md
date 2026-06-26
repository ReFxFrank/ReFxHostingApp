# ReFx — App Store Connect listing (copy/paste)

Everything App Store Connect asks for, written and ready to paste. Character
limits are noted and **verified** (see the counts table at the bottom). All copy
is accurate to the **public App Store build**, where in-app purchasing/plan
changes are disabled (billing is view-only; payments happen on the web) — so the
description never claims a feature a reviewer can't see.

Bundle ID: `com.refx.app` · Free · Min iOS 16 · iPhone only.

---

## A. App Information  → App Store Connect ▸ App Information
*(set once; applies to every version)*

### App Name — max 30
**Recommended:** `ReFx — Game Server Hosting`  *(26)*

Alternatives:
- `ReFx Game Server Manager`  *(24)*
- `ReFx Server Manager`  *(19)*

> Apple ignores your app name and category words inside Search keywords, so
> putting "Game Server Hosting" in the name also helps discovery.

### Subtitle — max 30
**Recommended:** `Manage your servers anywhere`  *(28)*

Alternatives:
- `Game servers in your pocket`  *(27)*
- `Console, backups & live status`  *(30)*

### Privacy Policy URL  *(required)*
`https://refx.gg/privacy`

### Category
- **Primary:** Utilities
- **Secondary:** Developer Tools  *(optional but a good fit)*

### Content Rights
"Does your app contain, show, or access third-party content?" → **No** (the app
only displays the signed-in user's own hosting data).

### Age Rating  → answer the questionnaire all **None** → **4+**
No objectionable content, no user-generated content shown publicly, no web
browser, unrestricted web access **No**.

---

## B. Pricing & Availability
- **Price:** Free (Tier 0)
- **Availability:** All territories (adjust if you only serve some regions)

---

## C. Version Information  → (version) ▸ this is 1.0

### Promotional Text — max 170  *(editable any time without re-review; paste as one line)*
```
Console, files, backups and live status for every game server you host — now with instant push alerts when a server goes down, an invoice is due, or support replies.
```

### Keywords — max 100, comma-separated, **no spaces**
```
game,server,hosting,minecraft,console,sftp,backup,teamspeak,rust,ark,valheim,modpack,control,panel
```

> Don't repeat words already in the app name ("game", "server", "hosting") if you
> need room — Apple already indexes those. The list above fits in 100 chars with
> them included; trim from the right if you change the name.

### Description — max 4000
```
ReFx puts your game servers in your pocket.

Sign in to your existing ReFx Hosting account and manage every server you own from one fast, native app — no laptop required.

MANAGE EVERY SERVER
• Live status at a glance — see what's running, starting, or stopped, with real-time CPU, memory, and player gauges
• Full web console with command history — start, stop, restart, and send commands from anywhere
• Browse and edit configuration files with a built-in editor
• Create, restore, and download backups
• Schedule automated tasks — restarts, commands, and backups on your timetable
• Manage MySQL databases

GAMES & CONTENT
• Minecraft tools — switch versions and loaders, and install plugins, mods, and modpacks
• Steam Workshop content, installed in a tap
• TeamSpeak voice-server administration
• Switch the game running on a server

BILLING & SUPPORT, BUILT IN
• View invoices, receipts, and billing history
• Open and reply to support tickets without leaving the app

STAY IN THE LOOP
• Push notifications when a server changes state, an invoice needs attention, or support replies
• Secure access with Face ID / Touch ID app lock

ReFx is a free companion to your existing hosting account. New accounts and payments are handled on our website; the app is for managing the servers you already run.

Questions or feedback? We're here: https://refx.gg/support
```

### Support URL  *(required)*
`https://refx.gg/support`

### Marketing URL  *(optional)*
`https://refx.gg`

### Copyright
`© 2026 ReFx`

### What's New in This Version
*(Not shown for the very first release. Use this for the next update; for 1.0 you
can leave it blank or use:)*
```
First release of the ReFx app. Manage your game servers on the go: live console,
files, backups, schedules, billing, support, and push notifications.
```

---

## D. App Review Information  → (version) ▸ App Review Information

### Sign-In required → **Yes**
Provide a working **customer** demo account (NOT staff/admin), with **2FA OFF**,
that already has **at least one server**, **one invoice**, and **one support
ticket** so every tab shows real content.

- **Username:** `<demo customer email>`  ← you fill in
- **Password:** `<demo password>`  ← you fill in

### Contact Information
First name / last name / phone number / email of someone who can answer App
Review quickly.

### Notes  *(paste into the Notes field)*
```
ReFx is a free companion app for an existing game-server hosting service. Users sign in with an account they already have on our website and manage servers they already own — live console, files, backups, schedules, databases, mods/modpacks, billing history, and support tickets.

There is no in-app purchase and no card entry anywhere in the app. Accounts are created and all payments are made on our website (a real-world hosting service consumed outside the app, per Guideline 3.1.3). Invoices are viewable in the app but cannot be paid inside it.

Demo account: the credentials in Sign-In Information are a customer account with 2FA disabled and a sample server, invoice, and ticket already attached, so all screens are populated.

The live console uses a Socket.IO (WebSocket) connection to the user's server — this is the only third-party SDK and it carries no analytics or tracking.
```

---

## E. App Privacy  → see `docs/AppStoreSubmission.md` §1
Already documented and matched to `PrivacyInfo.xcprivacy`: Email, Name, Physical
address (billing), Device ID (push token), Customer-support content — all
**Linked to user, App Functionality, NOT used for tracking**. No ATT prompt.

---

## F. Screenshots  → you capture these (specs only, no copy)

The app ships **iPhone-only** for launch, so only one set is required:
- **iPhone 6.9"** (15/16 Pro Max) — 1320 × 2868. **Required.**

*(No iPad set needed — iPad support is deferred to a later version.)*

Suggested order, captured on the demo account so they're populated: Servers list
→ Server detail (status + gauges) → Live console → Files or Backups → Billing /
invoices → Notifications.

---

## Character-count verification

| Field | Limit | Recommended copy | Count |
| --- | --- | --- | --- |
| App Name | 30 | ReFx — Game Server Hosting | 26 |
| Subtitle | 30 | Manage your servers anywhere | 28 |
| Promotional Text | 170 | (see above) | 165 |
| Keywords | 100 | (see above) | 98 |
| Description | 4000 | (see above) | 1364 |

> Every count above was verified character-for-character (Unicode code points,
> which is what App Store Connect counts). Re-verify if you edit the copy.
