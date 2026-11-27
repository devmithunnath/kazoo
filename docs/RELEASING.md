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

## Publishing a release and updating Homebrew

Kazoo's Homebrew cask lives in this repository (`Casks/kazoo.rb`), so the repo doubles as its own tap:

```bash
brew tap devmithunnath/kazoo https://github.com/devmithunnath/kazoo
brew install --cask devmithunnath/kazoo/kazoo
```

For each release:

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in the Kazoo target.
2. Build the zip and update the cask's version and checksum:

   ```bash
   Scripts/package.sh            # preview build (ad-hoc signed)
   ```

   `Scripts/build.sh` signs with your Developer ID or Apple Development certificate so users' Keychain
   permissions survive updates (see `docs/DEVELOPMENT.md`). For a notarized build, run `Scripts/release.sh` first, then zip `dist/Kazoo.app` the same way and update the
   checksum in `Casks/kazoo.rb`. Remove the cask's quarantine `postflight` block once builds are notarized.
3. Create a GitHub release tagged `v<version>` and attach `dist/Kazoo-<version>.zip`.
4. Commit and push `Casks/kazoo.rb`. Users get the update with `brew upgrade --cask kazoo`.

The cask URL points at the release asset, so push the cask only after the release asset is uploaded.
