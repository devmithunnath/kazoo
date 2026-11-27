cask "kazoo" do
  version "0.1.3"
  sha256 "ae71fd9aed683cebf58df8944cce7a144d60ab5545bed1f673d7d0a01cdaf0a3"

  url "https://github.com/devmithunnath/kazoo/releases/download/v#{version}/Kazoo-#{version}.zip"
  name "Kazoo"
  desc "AI usage meters in the MacBook notch"
  homepage "https://github.com/devmithunnath/kazoo"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Kazoo.app"

  # Preview builds are not notarized. Clear the download quarantine so Gatekeeper does not block the first
  # launch. Remove these steps once releases are signed with Developer ID and notarized.
  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "{{appdir}}/Kazoo.app"],
        must_succeed: false
  end

  uninstall quit: "com.pipboxes.kazoo"

  zap trash: [
    "~/Library/Application Support/Kazoo",
    "~/Library/Preferences/com.pipboxes.kazoo.plist",
  ]
end
