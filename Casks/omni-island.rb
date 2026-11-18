# Homebrew cask for OmniIsland. The release workflow rewrites `version` and
# `sha256` on every tagged release, so `brew upgrade` picks up new versions.
#
#   brew tap jadewisemann/dynamic-island https://github.com/jadewisemann/dynamic-island
#   brew install --cask omni-island
cask "omni-island" do
  version "0.10.1"
  sha256 "4ff683785e790f384b07ce49d7a21186041f606da74d25f11b143323e2b7700a"

  url "https://github.com/jadewisemann/dynamic-island/releases/download/v#{version}/OmniIsland.zip"
  name "OmniIsland"
  desc "Dynamic-island style workspace indicator for the OmniWM tiling window manager"
  homepage "https://github.com/jadewisemann/dynamic-island"

  conflicts_with cask: "omni-island@nightly"
  depends_on macos: ">= :sonoma"

  app "OmniIsland.app"
  # The app's executable doubles as the `omni-island` command (notify, hook).
  binary "#{appdir}/OmniIsland.app/Contents/MacOS/OmniIsland", target: "omni-island"

  # The app is signed with a self-signed certificate, not notarized by Apple,
  # so Gatekeeper would refuse to open it while it carries the quarantine flag.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/OmniIsland.app"],
                   must_succeed: false
    system_command "/usr/bin/open", args: ["#{appdir}/OmniIsland.app"], must_succeed: false
  end

  uninstall quit: "io.github.jadewisemann.omni-island"

  zap trash: "~/.config/omni-island"
end
