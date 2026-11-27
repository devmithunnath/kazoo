cask "kazoo" do
  version "0.1.2"
  sha256 "656cc0df1dceb610aed31d8de70eac2b59d0fb6b23582e2fc5f8258ed1638824"

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

  # Preview builds are ad-hoc signed, not notarized. Clear the download quarantine so Gatekeeper does not block
  # the first launch. Remove this block once releases are signed with Developer ID and notarized.
  postflight do
    system_command "/usr/bin/xattr",
                   args:         ["-dr", "com.apple.quarantine", "#{appdir}/Kazoo.app"],
                   must_succeed: false
  end

  uninstall quit: "com.pipboxes.kazoo"

  zap trash: [
    "~/Library/Application Support/Kazoo",
    "~/Library/Preferences/com.pipboxes.kazoo.plist",
  ]
end
