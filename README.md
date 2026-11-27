# Kazoo

Look at your MacBook's notch to see how much AI usage you have left. Click it to compare providers.
Connect accounts from a normal Mac window. A PipBoxes product.

Kazoo is a native macOS 14+ app written in Swift, SwiftUI and AppKit. It gets provider data from
[CodexBar](https://github.com/steipete/CodexBar)'s `CodexBarCore` (MIT), pinned to **v0.85.0**
(`5dd48cab770a326691b25a124d37ffee12c5f7ac`).

| Provider | What it shows | How you connect |
|---|---|---|
| Codex | 5-hour and weekly allowance, each with its own reset; works with accounts that report only one window | **Use account on this Mac** (reads `~/.codex`), or **Sign in with Codex CLI** |
| Claude | 5-hour session and weekly (all models); model-specific weekly limits listed underneath | **Use account on this Mac** (Claude Code sign-in), or **Sign in with Claude Code** |
| Cursor | Included plan usage, billing cycle end, on-demand spend | **Use browser sign-in** (imports the cursor.com session cookie) |
| GitHub Copilot | Premium-request quota, or AI credits used plus the billing period | **Sign in with GitHub** (device code in your browser) |
| Gemini CLI | Pro, Flash and Flash Lite buckets, each with its own reset. The source is labeled Gemini CLI | **Use Gemini CLI sign-in** (reads `~/.gemini`) |
| OpenCode | Workspace spend over 30 days, prepaid balance, or subscription windows | **Connect workspace** (browser session, optional workspace ID) |
| OpenAI API | Organization spend today and over the last 7 days, plus a daily chart | **Add admin key** (`sk-admin-…`, stored in Keychain) |

## Build and run

You need Xcode 26 (Swift 6.2) on macOS 14 or later.

```bash
Scripts/build.sh            # Release build → dist/Kazoo.app (ad-hoc signed)
```

```bash
open dist/Kazoo.app
```

You can also open `Kazoo.xcodeproj` in Xcode and run the **Kazoo** scheme. Xcode resolves the
local `KazooKit` package and the pinned CodexBar revision on its own.

- **Try it without accounts:** check `--demo` in the scheme's arguments, or run
  `open dist/Kazoo.app --args --demo`. Demo mode runs in memory with labeled sample data and never
  touches your saved accounts. You can also turn it on in the Connections window ("Explore with demo data").
- **Tests:** run `cd KazooKit && swift test`. There are 36 tests, covering units and timing, the
  snapshot mapping for all seven providers, the store's refresh and recovery behavior, and routing.
- **Live probe (developer):** run `cd KazooKit && swift run kazoo-probe claude cli`. It prints the
  normalized reading the notch would show, and never prints credentials. Copilot and OpenAI read
  `KAZOO_COPILOT_TOKEN` / `KAZOO_OPENAI_ADMIN_KEY` from the environment.
- **Visual QA without screen recording:** run `cd KazooKit && swift run kazoo-render /tmp/kazoo-renders`.
  It renders every panel state to PNG from fixtures.

## Using it

- **Collapsed notch:** your favorite provider's short name sits left of the camera and one reading sits
  on the right, such as `31% weekly left` or `$2.80 today`. The camera area stays empty. The strip is
  only as wide as its text.
- **Click the notch:** with one provider you see its detail. With several you see an overview of up to
  three pinned providers, then **All N providers**. Press Esc or click outside to dismiss. The panel
  never activates Kazoo, so your app keeps focus. Shortcuts: `1`–`3` open the pinned providers,
  `⌘[` goes back, `⌘R` refreshes, `⌘,` opens Settings.
- **Right-click the notch** to get Refresh, Connections, Settings and Quit.
- **Displays without a notch:** a menu-bar item shows the same panel in a popover. It also appears when
  the notched display is not your primary display, or when you turn on **Always show menu bar item**.
  Placement is checked again when displays change and after wake.
- **Settings:** choose the favorite, reorder or replace pinned providers, set the display name and
  refresh interval, and turn on open at login and demo mode. Third-party notices are here too.

### Readings

- For Codex and Claude, the summary is the **lowest remaining account-wide window**, with its name
  shown. A limit on one model never makes the whole account look exhausted.
- A value the provider didn't report shows as `—`. A reported zero shows as `0%`.
- Dollar amounts never get a gauge. Copilot credits get a gauge only when a denominator is known.
- The lit squares and the percentage label come from the same rounded number.
- Countdowns use provider timestamps. At zero, the panel shows *Reset due · confirming…*, refreshes once,
  and waits for the provider before showing a refilled quota.
- After a temporary failure (offline or rate limited), the last good reading stays visible with its
  age, and refreshes back off from 1 to 30 minutes. A disconnect or a switch to another account clears
  the old account's data right away.

### Credentials

- API keys and GitHub device tokens are stored in Keychain under `com.pipboxes.kazoo.credentials`.
- Sign-ins owned by other tools (`~/.codex`, Claude Code, `~/.gemini`, browser cookies) are read where
  they already are, and only after you click the provider's connect action. Disconnecting removes only
  what Kazoo stored.
- Ordinary preferences are kept in `UserDefaults`. The last good readings, which contain no secrets, are
  kept in `~/Library/Application Support/Kazoo/readings.json`.

## Project layout

```
Kazoo.xcodeproj      App target (shared scheme "Kazoo")
Kazoo/               AppKit shell: notch panels, menu-bar fallback, windows, app lifecycle
KazooKit/               Swift package: models, the UsageSource interface, CodexBarCore adapter, store, SwiftUI views
  Sources/KazooKit/Engine/CodexBarUsageSource.swift   the single bridge to CodexBarCore
  Sources/KazooKit/Engine/SnapshotMapper.swift        UsageSnapshot → UsageReading for all seven providers
  Sources/KazooKit/Store/UsageStore.swift             refresh, dedupe, backoff, generations, persistence
  Sources/KazooKit/UI/                                notch panel, Connections, Settings, previews
Scripts/build.sh        reproducible local build
Scripts/make_icon.swift regenerates Kazoo/Assets.xcassets/AppIcon.appiconset (swift Scripts/make_icon.swift <dir>)
Scripts/release.sh      Developer ID signing + notarization + stapling
```

Every provider sits behind one app-owned protocol, `UsageSource.fetch(_:) -> UsageReading`. The views
only see `UsageReading`/`Meter`, so a change in one provider never reaches the notch views. The display
name is configurable in Settings and through the `KAZOO_DISPLAY_NAME` build setting.

## Direct distribution (Developer ID + notarization)

1. Create a **Developer ID Application** certificate (Xcode → Settings → Accounts → Manage
   Certificates, or developer.apple.com).
2. Store notarization credentials once:

   ```bash
   xcrun notarytool store-credentials kazoo-notary --apple-id "<apple-id>" --team-id "<TEAMID>" --password "<app-specific-password>"
   ```

3. Build, sign, notarize and staple:

   ```bash
   DEVELOPER_ID="Developer ID Application: PipBoxes (TEAMID)" TEAM_ID=TEAMID NOTARY_PROFILE=kazoo-notary Scripts/release.sh
   ```

   This produces `dist/Kazoo-<version>.zip` with a stapled app. Hardened Runtime is on. The app is
   not sandboxed, because it has to read CLI sign-ins, run provider CLIs and import browser sessions, the
   same as CodexBar.

## License notices

Kazoo bundles CodexBarCore (MIT), QuickJS (MIT), SweetCookieKit (MIT), swift-crypto, swift-log and
swift-asn1 (Apache 2.0). The full texts are in `KazooKit/Sources/KazooKit/Resources/ThirdPartyNotices.txt`
and in Settings → About → Third-party notices. Code adapted from CodexBar's app target and CLI (the login
runner and the fetch-context assembly) is marked in source and stays under CodexBar's MIT license.

## Verification status (2026-11-26)

| Provider | Status | Detail |
|---|---|---|
| Claude | **live-tested** | A real reading through CodexBarCore on this Mac: 5-hour session 92% left, resets in 4h 47m (CLI source). Weekly was not reported and correctly stayed absent. The GUI connect flow has not been clicked through. |
| Codex | **live-tested (error path)** · fixture-tested reading | A real response, correctly classified as **Sign-in expired**: the local `~/.codex/auth.json` needs `codex login`, and Codex CLI is not on PATH. A successful reading is blocked until you sign in again. |
| Gemini CLI | **live-tested (not-signed-in path)** · fixture-tested reading | Correctly classified as not signed in; Gemini CLI is not installed here. The Connections window shows the install link and **Check again**. |
| Cursor | fixture-tested · **blocked** | There is no Cursor session on this Mac. Importing browser cookies brings up macOS Keychain prompts that you have to approve. |
| GitHub Copilot | fixture-tested · **blocked** | The device flow needs you to approve the code in a browser signed in to GitHub. |
| OpenCode | fixture-tested · **blocked** | Needs a signed-in opencode.ai browser session. |
| OpenAI API | fixture-tested · **blocked** | Needs an organization Admin key. |

**Verified on this Mac (MacBook Pro, built-in notch 185×32 pt, normal scale):**

- Debug and Release builds succeed.
- The collapsed strip is centered on the camera housing and flush with the top. The expanded panel is
  centered and the collapsed strip hides while it is open.
- First launch with zero accounts opens Connections.
- The panel did not take focus from the foreground app.
- Every panel state renders correctly (see `kazoo-render`).

**Still needs hands-on QA:** the screen was locked during this session, and there was no
screen-recording or accessibility-automation permission.

- Clicking through each connect flow, quit and relaunch
- An external display, and sleep and wake
- Keyboard navigation in the panel
- VoiceOver labels (implemented on every column, row and the collapsed notch)
- Reduce Motion (animations are skipped when it is on)
- Running with one, three and seven live providers
- Notarization, which is blocked because no Developer ID Application certificate is installed
# kazoo
