# Releasing

Kazoo ships outside the Mac App Store as a Developer ID–signed, notarized app. It is not sandboxed, because it
reads CLI sign-ins, runs provider CLIs and imports browser sessions, the same as CodexBar. Hardened Runtime is on.

1. Create a **Developer ID Application** certificate (Xcode → Settings → Accounts → Manage Certificates).
2. Store notarization credentials once:

   ```bash
   xcrun notarytool store-credentials kazoo-notary --apple-id "<apple-id>" --team-id "<TEAMID>" --password "<app-specific-password>"
   ```

3. Build, sign, notarize and staple:

   ```bash
   DEVELOPER_ID="Developer ID Application: PipBoxes (TEAMID)" TEAM_ID=TEAMID NOTARY_PROFILE=kazoo-notary Scripts/release.sh
   ```

The script produces `dist/Kazoo-<version>.zip` containing the stapled app. Bump `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` in the Kazoo target before each release.
