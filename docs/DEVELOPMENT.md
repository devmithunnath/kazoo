# Development

## Requirements

- macOS 14 Sonoma or later
- Xcode 26 (Swift 6.2)

## Build

```bash
Scripts/build.sh            # Release → dist/Kazoo.app (ad-hoc signed)
Scripts/build.sh Debug      # Debug build
```

Or open `Kazoo.xcodeproj` and run the **Kazoo** scheme. Xcode resolves the local `KazooKit` package and the
pinned CodexBar revision automatically.

Launch arguments (enable them in the scheme, or pass with `open dist/Kazoo.app --args …`):

| Argument | Effect |
|---|---|
| `--demo` | In-memory session with labeled sample data for all seven providers. Never touches saved accounts or Keychain. |
| `--favorite <id>` | With `--demo`: provider shown in the collapsed notch (`codex`, `claude`, `cursor`, `copilot`, `gemini`, `opencode`, `openai`). |
| `--pinned <ids>` | With `--demo`: comma-separated pinned providers. |
| `--open-panel` | Opens the expanded panel at launch. |

## Tests

```bash
cd KazooKit && swift test
```

The suite covers units and timing (gauge math, countdowns, missing vs zero), snapshot mapping for all seven
providers against CodexBarCore types, store behavior (refresh dedupe, backoff, offline cache, expired sign-in,
account switches mid-request, reset confirmation, demo isolation, permission prompts only on user actions), and
panel routing.

## Developer tools

```bash
cd KazooKit
swift run kazoo-probe claude cli          # fetch one live provider, print the normalized reading
swift run kazoo-render /tmp/kazoo-renders # render every panel state to PNG from fixtures
```

`kazoo-probe` never prints credentials. Copilot and OpenAI read `KAZOO_COPILOT_TOKEN` and
`KAZOO_OPENAI_ADMIN_KEY` from the environment.

The app icon is drawn in code: `swift Scripts/make_icon.swift Kazoo/Assets.xcassets/AppIcon.appiconset`.

## Architecture

```
Kazoo.xcodeproj         App target (shared scheme "Kazoo")
Kazoo/                  AppKit shell: notch panels, menu-bar fallback, windows, lifecycle
KazooKit/               Swift package
  Engine/UsageSource.swift          the one app-owned provider interface
  Engine/CodexBarUsageSource.swift  the single bridge to CodexBarCore
  Engine/SnapshotMapper.swift       UsageSnapshot → UsageReading for all providers
  Store/UsageStore.swift            refresh, dedupe, backoff, account generations, persistence
  Connect/                          setup guides, CLI login runner, GitHub device flow
  UI/                               notch panel, Connections, Settings, previews
Scripts/                build, release, icon
```

Every provider sits behind `UsageSource.fetch(_:) -> UsageReading`. Views only see `UsageReading` and `Meter`,
so a change in one provider never reaches the notch views.

**Notch placement.** macOS has no notch API. Kazoo measures the camera housing from
`NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`, then places two borderless,
non-activating `NSPanel`s just above the menu bar: a collapsed strip sized to its text, and the expanded panel.
Placement is recomputed when displays change and after wake. Without a notch, an `NSStatusItem` popover shows
the same SwiftUI panel.

**Refresh policy.** One in-flight request per provider (duplicates join it), exponential backoff from 1 to
30 minutes on rate limits and transient failures, last good reading kept with its age, and a per-provider
generation counter that discards results from disconnected or switched accounts. Only user-initiated fetches
may show macOS Keychain prompts.

## Verification status

| Provider | Status |
|---|---|
| Claude | Live-tested: real reading through CodexBarCore (CLI source) |
| Codex | Live-tested error path (expired sign-in classified correctly); reading fixture-tested |
| Gemini CLI | Live-tested not-signed-in path; reading fixture-tested |
| Cursor, GitHub Copilot, OpenCode, OpenAI API | Fixture-tested; live accounts not yet exercised |

Still to verify by hand: every connect flow end to end, external displays, sleep and wake, keyboard
navigation, VoiceOver, Reduce Motion, and one, three and seven live providers.
