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
  version "0.10.1-nightly.80"
  sha256 "aa910e0f31d8b3f2798c699048570cf009fb05b119c49fc0a106cdae4bb6ae92"

  url "https://github.com/jadewisemann/dynamic-island/releases/download/nightly/OmniIsland-#{version}.zip"
  name "OmniIsland Nightly"
  desc "Nightly build of the OmniWM dynamic-island workspace indicator"
  homepage "https://github.com/jadewisemann/dynamic-island"

  conflicts_with cask: "omni-island"
  depends_on macos: :sonoma

  app "OmniIsland.app"
  # The app's executable doubles as the `omni-island` command (notify, hook).
  binary "#{appdir}/OmniIsland.app/Contents/MacOS/OmniIsland", target: "omni-island"

  # Same as the stable cask: the app is self-signed, not notarized.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/OmniIsland.app"],
                          must_succeed: false
    run "/usr/bin/open", args: ["{{appdir}}/OmniIsland.app"], must_succeed: false
  end

  uninstall quit: "io.github.jadewisemann.omni-island"

  zap trash: "~/.config/omni-island"
end
