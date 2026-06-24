# Getting ReFx onto your iPhone via TestFlight

This puts the app on your real iPhone (not just the Simulator). It needs a paid
Apple Developer account and is done from the cloud Mac (Xcode). The project is
already prepped: app icon, version/build, and export-compliance flag are set.

## What only you can do (account + money)

1. **Enroll in the Apple Developer Program** — https://developer.apple.com/programs/
   - **$99/year**, tied to your Apple ID and identity (individual or your company).
   - Approval is usually quick (minutes–a day).
   - There is no way around this: Apple requires a paid membership to upload to
     TestFlight / install on a device beyond a 7-day free-provisioning build.

> Free alternative (no $99, but clunky): a free Apple ID can install the app
> directly from Xcode onto a cable-connected iPhone, but it **expires after 7
> days** and can't use TestFlight. For real testing, do the $99 enrollment.

## One-time setup on the cloud Mac

1. **Sign Xcode into your Apple ID**: Xcode ▸ Settings ▸ Accounts ▸ **+** ▸ Apple
   ID. Your Developer Team appears once enrollment is active.
2. Open the project, select the **ReFxApp** target ▸ **Signing & Capabilities**:
   - Check **Automatically manage signing**.
   - Set **Team** to your developer team.
   - **Bundle Identifier**: `com.refx.app` (default). If Apple says it's taken,
     change it (e.g. `gg.refx.app`) — edit `PRODUCT_BUNDLE_IDENTIFIER` in
     `project.yml`, re-run `xcodegen generate`, and use the new id everywhere.

## Archive & upload (each release)

1. Set the run destination (top toolbar) to **Any iOS Device (arm64)** — *not* a
   Simulator. Archiving is disabled for simulator destinations.
2. Pick the **ReFxApp (Release)** scheme.
3. **Product ▸ Archive**. Wait for the build; the Organizer window opens.
4. Select the archive ▸ **Distribute App** ▸ **TestFlight & App Store Connect** ▸
   **Upload**. Let Xcode manage signing. It uploads to App Store Connect.
   - First upload also creates the app record (or create it manually at
     https://appstoreconnect.apple.com ▸ Apps ▸ **+** with the same bundle id).
5. Bump the build number for the next upload (each must be unique): change
   `CURRENT_PROJECT_VERSION` in `project.yml` (e.g. `2`), `xcodegen generate`,
   re-archive. (`MARKETING_VERSION` = the user-facing version, bump for releases.)

## Turn on TestFlight & install

1. App Store Connect ▸ your app ▸ **TestFlight** tab. The build appears as
   "Processing" for a few minutes, then "Ready to Test".
2. Add yourself as an **Internal Tester** (Users with a role on the account — no
   review needed). For others, use **External Testers** (needs a quick Beta App
   Review the first time).
3. Install **TestFlight** from the App Store on your iPhone, sign in with the
   same Apple ID, and your app shows up to install.
4. Open it and sign in with your **refx.gg** account — it talks to the live
   `api.refx.gg` exactly like the Simulator build.

## Notes

- The first TestFlight build asks for an **export-compliance** answer; we already
  set `ITSAppUsesNonExemptEncryption = false` (standard HTTPS only), so it won't
  prompt you each time.
- The `iOS Build & Test` CI workflow builds + tests every push but does not
  upload. Automated TestFlight delivery is the separate `TestFlight Upload`
  workflow below.

---

## Automated TestFlight uploads (CI)

The **`TestFlight Upload`** GitHub Actions workflow archives, signs (in CI, via
an App Store Connect API key — no cert/profile export needed), and uploads to
TestFlight. You trigger it manually from the **Actions** tab, so builds are
intentional.

### One-time setup

1. **Active Apple Developer Program membership** (the $99 enrollment above).
2. **Create the app record** in App Store Connect ▸ Apps ▸ **+** ▸ New App,
   bundle id **`com.refx.app`** (must match). A build can't upload to a
   non-existent app.
3. **Generate an App Store Connect API key**: App Store Connect ▸ **Users and
   Access** ▸ **Integrations** (Keys) ▸ App Store Connect API ▸ **+**.
   - Access role: **App Manager** (or Admin).
   - Download the **`.p8`** file (you only get it once) and note the **Key ID**
     and **Issuer ID**.
4. **Find your Team ID**: developer.apple.com ▸ Membership ▸ Team ID (10 chars).
5. **Add repo secrets** (GitHub ▸ Settings ▸ Secrets and variables ▸ Actions ▸
   New repository secret):

   | Secret | Value |
   |---|---|
   | `ASC_KEY_ID` | the API Key ID |
   | `ASC_ISSUER_ID` | the API key Issuer ID (UUID) |
   | `ASC_KEY_P8_BASE64` | the `.p8` file, base64-encoded |
   | `APPLE_TEAM_ID` | your 10-char Team ID |

   To base64 the key (on the Mac or any terminal):
   ```bash
   base64 -i AuthKey_XXXXXXXX.p8 | pbcopy   # paste as ASC_KEY_P8_BASE64
   ```

### Running it

- **Actions** tab ▸ **TestFlight Upload** ▸ **Run workflow**. Optionally set a
  build number (defaults to the run number; each upload must be unique).
- ~10–15 min later the build appears in App Store Connect ▸ TestFlight as
  "Processing", then "Ready to Test". Add testers as above.

The first run also registers the bundle id / provisioning automatically
(`-allowProvisioningUpdates`). If it fails with "no app", create the app record
(step 2) and re-run.
