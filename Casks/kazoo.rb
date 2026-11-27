cask "kazoo" do
  version "0.1.5"
  sha256 "35f584f4f2213f4e3f97588af9ada72adebe1a29590782946c6ab2db40359906"

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
