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
- The CI workflow builds + tests every push, but it does **not** upload to
  TestFlight — that needs your App Store Connect API key as a secret. The manual
  Archive ▸ Upload above is the simplest path for now; automated TestFlight
  delivery from CI can be added later if you want it.
