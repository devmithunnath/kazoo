# Uninstalling Kazoo

These steps remove Kazoo and everything it stores on your Mac. Run them in order in Terminal.

## 1. Uninstall the app

**Installed with Homebrew.** This quits Kazoo, removes `/Applications/Kazoo.app`, and with `--zap` also deletes
Kazoo's Application Support folder and preferences:

```bash
brew uninstall --cask --zap devmithunnath/kazoo/kazoo
```

Then remove the tap:

```bash
brew untap devmithunnath/kazoo
```

**Installed manually.** Quit Kazoo (right-click the notch → **Quit Kazoo**), then drag **Kazoo.app** from
Applications to the Trash.

## 2. Remove remaining files

Delete the cache, network storage, update logs and files from Kazoo's earlier name (KazooBar):

```bash
rm -rf ~/Library/Caches/com.pipboxes.kazoo ~/Library/HTTPStorages/com.pipboxes.kazoo ~/Library/Logs/Kazoo "$HOME/Library/Application Support/Kazoo" "$HOME/Library/Application Support/KazooBar" "${TMPDIR}Kazoo"
```

## 3. Remove the provider engine's files

Kazoo uses CodexBar's provider engine, which keeps small state files under the CodexBar name.

> [!WARNING]
> Skip this step if you also use the CodexBar app. It shares these locations.

```bash
rm -rf "$HOME/Library/Application Support/CodexBar"
```

```bash
defaults delete com.steipete.codexbar 2>/dev/null; rm -f ~/Library/Preferences/com.steipete.codexbar.plist
```

## 4. Clear Kazoo's preferences

```bash
for d in com.pipboxes.kazoo com.pipboxes.kazoobar; do defaults delete "$d" 2>/dev/null; rm -f ~/Library/Preferences/"$d".plist; done
```

## 5. Delete saved keys from Keychain

Removes any GitHub Copilot token or OpenAI admin key Kazoo saved, including ones saved under the old name. It is
safe to run even if there are none:

```bash
for s in com.pipboxes.kazoo.credentials com.pipboxes.kazoobar.credentials; do while security delete-generic-password -s "$s" >/dev/null 2>&1; do :; done; done
```

## What is not removed

- **Other tools' sign-ins.** Codex (`~/.codex`), Claude Code, Gemini CLI, Antigravity and your browser sessions
  belong to those tools. Kazoo only read them, so they stay signed in.
- **Kazoo's entry in Claude Code's Keychain access list.** If you allowed Kazoo to read Claude Code's sign-in, Kazoo
  stays listed there. This is harmless. To remove it, open **Keychain Access**, find **Claude Code-credentials**,
  and remove Kazoo under **Access Control**.
- **Open at login.** If you turned it on, macOS drops the login item once the app is deleted. You can confirm in
  **System Settings → General → Login Items & Extensions**.

## For developers

If you built Kazoo from source, also remove:

- **Developer tool preferences**, created by `kazoo-probe`, `kazoo-render` and test runs:

  ```bash
  for d in kazoo-probe kazoo.probe kazoo.render; do defaults delete "$d" 2>/dev/null; rm -f ~/Library/Preferences/"$d".plist; done
  ```

  ```bash
  for f in ~/Library/Preferences/kazoo.tests.*.plist(N); do defaults delete "$(basename "$f" .plist)" 2>/dev/null; rm -f "$f"; done
  ```

  The second command uses zsh syntax, the default shell on macOS.

- **The source folder.** Delete your clone of the repository. Its `build/` and `KazooKit/.build/` folders can take
  about 2 GB.
