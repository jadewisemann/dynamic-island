# Homebrew cask for the nightly channel of OmniIsland: a build of every push
# to main. The build workflow rewrites `version` and `sha256` after each
# nightly build, so `brew upgrade` picks up the newest main.
#
#   brew tap jadewisemann/dynamic-island https://github.com/jadewisemann/dynamic-island
#   brew install --cask omni-island@nightly
#
# Both channels install the same OmniIsland.app with the same signature, so
# switching keeps the Accessibility permission and ~/.config/omni-island.
cask "omni-island@nightly" do
  version "0.9.1-nightly.72"
  sha256 "ea96d6db8129055a0e2401a1cfe04f0a523f0e3ba3d98835b5a965450f0f90d0"

  url "https://github.com/jadewisemann/dynamic-island/releases/download/nightly/OmniIsland-#{version}.zip"
  name "OmniIsland Nightly"
  desc "Nightly build of the OmniWM dynamic-island workspace indicator"
  homepage "https://github.com/jadewisemann/dynamic-island"

  conflicts_with cask: "omni-island"
  depends_on macos: ">= :sonoma"

  app "OmniIsland.app"
  # The app's executable doubles as the `omni-island` command (notify, hook).
  binary "#{appdir}/OmniIsland.app/Contents/MacOS/OmniIsland", target: "omni-island"

  # Same as the stable cask: the app is self-signed, not notarized.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/OmniIsland.app"],
                   must_succeed: false
    system_command "/usr/bin/open", args: ["#{appdir}/OmniIsland.app"], must_succeed: false
  end

  uninstall quit: "io.github.jadewisemann.omni-island"

  zap trash: "~/.config/omni-island"
end
