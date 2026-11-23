# Homebrew cask for OmniIsland. The release workflow rewrites `version` and
# `sha256` on every tagged release, so `brew upgrade` picks up new versions.
#
#   brew tap jadewisemann/dynamic-island https://github.com/jadewisemann/dynamic-island
#   brew install --cask omni-island
cask "omni-island" do
  version "0.13.0"
  sha256 "c75cf50b7ae222f3fbb6a2e8c946c021c2f5be1d536b4c5454d8ddfc4920a77d"

  url "https://github.com/jadewisemann/dynamic-island/releases/download/v#{version}/OmniIsland.zip"
  name "OmniIsland"
  desc "Dynamic-island style workspace indicator for the OmniWM tiling window manager"
  homepage "https://github.com/jadewisemann/dynamic-island"

  conflicts_with cask: "omni-island@nightly"
  depends_on macos: :sonoma

  app "OmniIsland.app"
  # The app's executable doubles as the `omni-island` command (notify, hook).
  binary "#{appdir}/OmniIsland.app/Contents/MacOS/OmniIsland", target: "omni-island"

  # The app is signed with a self-signed certificate, not notarized by Apple,
  # so Gatekeeper would refuse to open it while it carries the quarantine flag.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/OmniIsland.app"],
                          must_succeed: false
    run "/usr/bin/open", args: ["{{appdir}}/OmniIsland.app"], must_succeed: false
  end

  uninstall quit: "io.github.jadewisemann.omni-island"

  zap trash: "~/.config/omni-island"
end
