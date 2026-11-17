# Homebrew cask for OmniIsland. The release workflow rewrites `version` and
# `sha256` on every tagged release, so `brew upgrade` picks up new versions.
#
#   brew tap jadewisemann/dynamic-island https://github.com/jadewisemann/dynamic-island
#   brew install --cask omni-island
cask "omni-island" do
  version "0.0.0"
  sha256 :no_check

  url "https://github.com/jadewisemann/dynamic-island/releases/download/v#{version}/OmniIsland.zip"
  name "OmniIsland"
  desc "Dynamic-island style workspace indicator for the OmniWM tiling window manager"
  homepage "https://github.com/jadewisemann/dynamic-island"

  depends_on macos: ">= :sonoma"

  app "OmniIsland.app"

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
